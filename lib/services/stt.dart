import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:cactus/models/types.dart';
import 'package:cactus/src/services/context.dart';
import 'package:cactus/src/services/api/huggingface.dart';
import 'package:cactus/src/utils/models/download.dart';
import 'package:cactus/services/config.dart';
import 'package:cactus/src/services/bindings.dart' as bindings;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CactusSTT {
  int? _handle;
  int? _streamHandle;
  bool _isInitialized = false;
  bool _isDownloading = false;
  bool _isStreamTranscribing = false;

  final String model;
  final CactusModelOptions options;

  static const String _defaultModel = 'whisper-small';
  static const _defaultQuantization = 'int8';
  static const String defaultPrompt =
      '<|startoftranscript|><|en|><|transcribe|><|notimestamps|>';
  static const _defaultTranscribeOptions =
      CactusSTTTranscribeOptions(maxTokens: 384);
  static const int _defaultEmbedBufferSize = 4096;

  final _handleLock = _AsyncLock();

  CactusSTT({String? model, CactusModelOptions? options})
      : model = model ?? _defaultModel,
        options = CactusModelOptions(
          quantization: options?.quantization ?? _defaultQuantization,
          pro: options?.pro ?? false,
        );

  Future<String> _resolveModelPath() async {
    if (_isModelPath(model)) return model;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models/${getModelName()}';
  }

  Future<void> download({CactusProgressCallback? onProgress}) async {
    if (_isDownloading) return;
    _isDownloading = true;
    try {
      if (await DownloadService.modelExists(getModelName())) return;

      final currentModel = await HuggingFace.getModel(model);
      if (currentModel == null) {
        throw Exception('Failed to get model $model');
      }

      final quantInfo = currentModel.quantization[options.quantization];
      if (quantInfo == null) {
        throw Exception(
            'Model $model does not have ${options.quantization} quantization');
      }

      String downloadUrl;
      if (options.pro && quantInfo.pro != null) {
        downloadUrl = quantInfo.pro!.apple;
      } else {
        downloadUrl = quantInfo.url;
      }

      final actualFilename =
          downloadUrl.split('?').first.split('/').last;
      final task = DownloadTask(
        url: downloadUrl,
        filename: actualFilename,
        folder: getModelName(),
      );

      final success =
          await DownloadService.downloadAndExtractModels([task], onProgress);
      if (!success) {
        throw Exception(
            'Failed to download and extract model $model from $downloadUrl');
      }
    } finally {
      _isDownloading = false;
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;

    final modelPath = await _resolveModelPath();
    final cacheLocation = (await getApplicationDocumentsDirectory()).path;
    CactusConfig.setTelemetryEnvironment(cacheLocation);

    final result = await CactusContext.initContext(modelPath, 512);
    _handle = result.$1;

    if (_handle == null &&
        !await DownloadService.modelExists(getModelName())) {
      debugPrint(
          'Failed to initialize model at $modelPath, downloading...');
      await download();
      return init();
    }

    if (_handle == null) {
      throw Exception('Failed to initialize model at $modelPath');
    }

    _isInitialized = true;
  }

  Future<CactusSTTTranscribeResult> transcribe({
    required dynamic audio,
    String? prompt,
    CactusSTTTranscribeOptions? options,
    CactusTokenCallback? onToken,
  }) async {
    await init();

    return _handleLock.synchronized(() async {
      final currentHandle = _handle;
      if (currentHandle == null) {
        throw Exception('Model not initialized');
      }

      final effectivePrompt = prompt ?? defaultPrompt;
      final effectiveOptions = options ?? _defaultTranscribeOptions;

      String? audioFilePath;
      List<int>? pcmData;
      if (audio is String) {
        audioFilePath = audio;
      } else if (audio is List<int>) {
        pcmData = audio;
      } else {
        throw ArgumentError(
            'audio must be a String (filepath) or List<int> (PCM data)');
      }

      return CactusContext.transcribe(
        currentHandle,
        effectivePrompt,
        audioFilePath: audioFilePath,
        pcmData: pcmData,
        params: effectiveOptions,
      );
    });
  }

  Future<void> streamTranscribeStart({
    CactusSTTStreamTranscribeStartOptions? options,
  }) async {
    await init();

    final currentHandle = _handle;
    if (currentHandle == null) {
      throw Exception('Model not initialized');
    }

    final optionsMap = <String, dynamic>{};
    if (options?.confirmationThreshold != null) {
      optionsMap['confirmation_threshold'] = options!.confirmationThreshold;
    }
    if (options?.minChunkSize != null) {
      optionsMap['min_chunk_size'] = options!.minChunkSize;
    }
    if (options?.telemetryEnabled != null) {
      optionsMap['telemetry_enabled'] = options!.telemetryEnabled;
    }
    if (options?.language != null) {
      optionsMap['language'] = options!.language;
    }
    final optionsJson = jsonEncode(optionsMap);

    _streamHandle = await compute(
        _streamTranscribeStartInIsolate,
        {'handle': currentHandle, 'optionsJson': optionsJson});

    _isStreamTranscribing = true;
  }

  Future<CactusSTTStreamTranscribeProcessResult> streamTranscribeProcess({
    required List<int> audio,
  }) async {
    if (!_isStreamTranscribing || _streamHandle == null) {
      throw Exception(
          'Stream transcription not started. Call streamTranscribeStart() first.');
    }

    return compute(_streamTranscribeProcessInIsolate, {
      'streamHandle': _streamHandle!,
      'pcmData': audio is Uint8List ? audio : Uint8List.fromList(audio),
      'bufferSize': 4096,
    });
  }

  Future<CactusSTTStreamTranscribeStopResult> streamTranscribeStop() async {
    if (!_isStreamTranscribing || _streamHandle == null) {
      throw Exception(
          'Stream transcription not started. Call streamTranscribeStart() first.');
    }

    try {
      return await compute(_streamTranscribeStopInIsolate, {
        'streamHandle': _streamHandle!,
        'bufferSize': 4096,
      });
    } finally {
      _isStreamTranscribing = false;
      _streamHandle = null;
    }
  }

  Future<CactusSTTDetectLanguageResult> detectLanguage({
    required dynamic audio,
    CactusSTTDetectLanguageOptions? options,
  }) async {
    await init();

    final currentHandle = _handle;
    if (currentHandle == null) {
      throw Exception('Model not initialized');
    }

    String? audioFilePath;
    List<int>? pcmData;
    if (audio is String) {
      audioFilePath = audio;
    } else if (audio is List<int>) {
      pcmData = audio;
    } else {
      throw ArgumentError(
          'audio must be a String (filepath) or List<int> (PCM data)');
    }

    return CactusContext.detectLanguage(
      currentHandle,
      audioFilePath: audioFilePath,
      pcmData: pcmData,
    );
  }

  Future<CactusSTTAudioEmbedResult> audioEmbed({
    required String audioPath,
  }) async {
    await init();

    final currentHandle = _handle;
    if (currentHandle == null) {
      throw Exception('Model not initialized');
    }

    return compute(_audioEmbedInIsolate, {
      'handle': currentHandle,
      'audioPath': audioPath,
      'bufferSize': _defaultEmbedBufferSize,
    });
  }

  Future<void> stop() async {
    final currentHandle = _handle;
    if (currentHandle != null) {
      try {
        bindings.cactusStop(Pointer.fromAddress(currentHandle));
      } catch (e) {
        debugPrint('Error stopping model: $e');
      }
    }
  }

  Future<void> reset() async {
    await stop();
    final currentHandle = _handle;
    if (currentHandle != null) {
      CactusContext.resetContext(currentHandle);
    }
  }

  Future<void> destroy() async {
    if (!_isInitialized) return;
    await stop();
    if (_isStreamTranscribing) {
      try {
        await streamTranscribeStop();
      } catch (e) {
        debugPrint(
            'Error stopping stream transcription during destroy: $e');
      }
    }
    final currentHandle = _handle;
    if (currentHandle != null) {
      CactusContext.freeContext(currentHandle);
    }
    _handle = null;
    _streamHandle = null;
    _isInitialized = false;
  }

  Future<List<CactusModel>> getModels() async {
    final allModels = await HuggingFace.fetchModels();
    final sttModels =
        allModels.where((m) => m.capabilities.contains('transcription')).toList();
    for (var m in sttModels) {
      m.isDownloaded = await DownloadService.modelExists(m.slug);
    }
    return sttModels;
  }

  String getModelName() =>
      '$model-${options.quantization}${options.pro ? '-pro' : ''}';

  bool _isModelPath(String m) => m.startsWith('/') || m.startsWith('file://');
}

int _streamTranscribeStartInIsolate(Map<String, dynamic> params) {
  final handle = params['handle'] as int;
  final optionsJson = params['optionsJson'] as String;

  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);
  try {
    final stream = bindings.cactusStreamTranscribeStart(
      Pointer.fromAddress(handle),
      optionsJsonC,
    );
    return stream.address;
  } finally {
    calloc.free(optionsJsonC);
  }
}

CactusSTTStreamTranscribeProcessResult _streamTranscribeProcessInIsolate(
    Map<String, dynamic> params) {
  final streamHandle = params['streamHandle'] as int;
  final pcmData = params['pcmData'] as Uint8List;
  final bufferSize = params['bufferSize'] as int;

  final pcmBufferPtr = calloc<Uint8>(pcmData.length);
  final responseBuffer = calloc<Uint8>(bufferSize);

  try {
    final nativeList = pcmBufferPtr.asTypedList(pcmData.length);
    nativeList.setAll(0, pcmData);

    final result = bindings.cactusStreamTranscribeProcess(
      Pointer.fromAddress(streamHandle),
      pcmBufferPtr,
      pcmData.length,
      responseBuffer.cast<Utf8>(),
      bufferSize,
    );

    if (result > 0) {
      final responseText = utf8
          .decode(responseBuffer.asTypedList(result), allowMalformed: true)
          .trim();
      try {
        final json = jsonDecode(responseText) as Map<String, dynamic>;
        return CactusSTTStreamTranscribeProcessResult(
          success: json['success'] as bool? ?? true,
          confirmed: json['confirmed'] as String? ?? '',
          pending: json['pending'] as String? ?? '',
          bufferDurationMs:
              (json['buffer_duration_ms'] as num?)?.toDouble(),
          confidence: (json['confidence'] as num?)?.toDouble(),
          cloudHandoff: json['cloud_handoff'] as bool?,
          timeToFirstTokenMs:
              (json['time_to_first_token_ms'] as num?)?.toDouble() ?? 0.0,
          totalTimeMs:
              (json['total_time_ms'] as num?)?.toDouble() ?? 0.0,
          prefillTokens: json['prefill_tokens'] as int?,
          prefillTps: (json['prefill_tps'] as num?)?.toDouble(),
          decodeTokens: json['decode_tokens'] as int?,
          decodeTps: (json['decode_tps'] as num?)?.toDouble(),
          totalTokens: json['total_tokens'] as int?,
          ramUsageMb: (json['ram_usage_mb'] as num?)?.toDouble(),
        );
      } catch (e) {
        return CactusSTTStreamTranscribeProcessResult(
          success: false,
          confirmed: '',
          pending: '',
        );
      }
    } else {
      return CactusSTTStreamTranscribeProcessResult(
        success: false,
        confirmed: '',
        pending: '',
      );
    }
  } finally {
    calloc.free(pcmBufferPtr);
    calloc.free(responseBuffer);
  }
}

CactusSTTStreamTranscribeStopResult _streamTranscribeStopInIsolate(
    Map<String, dynamic> params) {
  final streamHandle = params['streamHandle'] as int;
  final bufferSize = params['bufferSize'] as int;

  final responseBuffer = calloc<Uint8>(bufferSize);

  try {
    final result = bindings.cactusStreamTranscribeStop(
      Pointer.fromAddress(streamHandle),
      responseBuffer.cast<Utf8>(),
      bufferSize,
    );

    if (result > 0) {
      final responseText = utf8
          .decode(responseBuffer.asTypedList(result), allowMalformed: true)
          .trim();
      try {
        final json = jsonDecode(responseText) as Map<String, dynamic>;
        return CactusSTTStreamTranscribeStopResult(
          success: json['success'] as bool? ?? true,
          confirmed: json['confirmed'] as String? ?? '',
        );
      } catch (e) {
        return CactusSTTStreamTranscribeStopResult(
            success: false, confirmed: '');
      }
    } else {
      return CactusSTTStreamTranscribeStopResult(
          success: false, confirmed: '');
    }
  } finally {
    calloc.free(responseBuffer);
  }
}

CactusSTTAudioEmbedResult _audioEmbedInIsolate(
    Map<String, dynamic> params) {
  final handle = params['handle'] as int;
  final audioPath = params['audioPath'] as String;
  final bufferSize = params['bufferSize'] as int;

  final audioPathC = audioPath.toNativeUtf8(allocator: calloc);
  final embeddingDimPtr = calloc<IntPtr>();
  final embeddingsBuffer = calloc<Float>(bufferSize);

  try {
    final result = bindings.cactusAudioEmbed(
      Pointer.fromAddress(handle),
      audioPathC,
      embeddingsBuffer,
      bufferSize * 4,
      embeddingDimPtr,
    );

    if (result > 0) {
      final actualDim = embeddingDimPtr.value;
      if (actualDim > bufferSize) {
        return CactusSTTAudioEmbedResult(embedding: []);
      }
      final embedding = <double>[];
      for (int i = 0; i < actualDim; i++) {
        embedding.add(embeddingsBuffer[i]);
      }
      return CactusSTTAudioEmbedResult(embedding: embedding);
    } else {
      return CactusSTTAudioEmbedResult(embedding: []);
    }
  } finally {
    calloc.free(audioPathC);
    calloc.free(embeddingDimPtr);
    calloc.free(embeddingsBuffer);
  }
}

class _AsyncLock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() fn) async {
    while (_completer != null) {
      await _completer!.future;
    }

    _completer = Completer<void>();

    try {
      return await fn();
    } finally {
      final completer = _completer;
      _completer = null;
      completer?.complete();
    }
  }
}
