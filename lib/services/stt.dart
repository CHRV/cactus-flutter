import 'dart:async';

import 'package:cactus/models/types.dart';
import 'package:cactus/context.dart';
import 'package:cactus/services/api/huggingface.dart';
import 'package:cactus/utils/models/download.dart';
import 'package:cactus/utils/async_lock.dart';
import 'package:cactus/utils/model_utils.dart';
import 'package:cactus/services/config.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CactusSTT {
  CactusContext? _context;
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

  final _handleLock = AsyncLock();

  CactusSTT({String? model, CactusModelOptions? options})
      : model = model ?? _defaultModel,
        options = CactusModelOptions(
          quantization: options?.quantization ?? _defaultQuantization,
          pro: options?.pro ?? false,
        );

  Future<String> _resolveModelPath() async {
    if (isModelPath(model)) return model.replaceFirst('file://', '');
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models/${modelName(model, options)}';
  }

  Future<void> download(
      {String? model, CactusProgressCallback? onProgress}) async {
    if (_isDownloading) return;
    _isDownloading = true;
    try {
      final effectiveModel = model ?? this.model;
      if (await DownloadService.modelExists(
          '$effectiveModel-${options.quantization}${options.pro ? '-pro' : ''}'))
        return;

      final currentModel = await HuggingFace.getModel(effectiveModel);
      if (currentModel == null) {
        throw CactusException('Failed to get model $effectiveModel');
      }

      final quantInfo = currentModel.quantization[options.quantization];
      if (quantInfo == null) {
        throw CactusException(
            'Model $effectiveModel does not have ${options.quantization} quantization');
      }

      String downloadUrl;
      if (options.pro && quantInfo.pro != null) {
        downloadUrl = quantInfo.pro!.apple;
      } else {
        downloadUrl = quantInfo.url;
      }

      final actualFilename = downloadUrl.split('?').first.split('/').last;
      final task = DownloadTask(
        url: downloadUrl,
        filename: actualFilename,
        folder:
            '$effectiveModel-${options.quantization}${options.pro ? '-pro' : ''}',
      );

      final success =
          await DownloadService.downloadAndExtractModels([task], onProgress);
      if (!success) {
        throw CactusException(
            'Failed to download and extract model $effectiveModel from $downloadUrl');
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

    _context = await CactusContext.initContext(
      modelPath: modelPath,
    );

    if (_context == null &&
        !await DownloadService.modelExists(getModelName())) {
      debugPrint('Failed to initialize model at $modelPath, downloading...');
      await download();
      return init();
    }

    if (_context == null) {
      throw CactusException('Failed to initialize model at $modelPath');
    }

    _isInitialized = true;
  }

  Future<void> initializeModel({String? model, CactusInitParams? params}) =>
      init();

  Future<void> downloadModel({
    required String model,
    String? quantization,
    bool pro = false,
    CactusProgressCallback? onProgress,
  }) =>
      download(onProgress: onProgress);

  void unload() {
    _context?.destroy();
    _context = null;
    _isInitialized = false;
  }

  Future<List<VoiceModel>> getVoiceModels() async {
    final registry = await HuggingFace.getRegistry();
    return registry.values
        .where((m) => m.capabilities.contains('transcription'))
        .toList();
  }

  /// Transcribe via isolated FFI call. Uses Isolate.spawn because
  /// cactusTranscribe streams tokens through a Dart callback.
  Future<CactusSTTTranscribeResult> transcribe({
    required dynamic audio,
    String? prompt,
    CactusSTTTranscribeOptions? options,
    CactusTokenCallback? onToken,
  }) async {
    await init();

    return _handleLock.synchronized(() async {
      if (_context == null) {
        throw CactusException('Model not initialized');
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

      return CactusContext.transcribeAt(
        handleAddress: _context!.address,
        audioPath: audioFilePath,
        prompt: effectivePrompt,
        options: effectiveOptions,
        onToken: onToken,
        pcmData: pcmData,
      );
    });
  }

  Future<CactusTranscriptionResult> transcribeStream({
    required List<int> audio,
    List<int>? audioStream,
    String? audioFilePath,
    CactusTokenCallback? onToken,
  }) async {
    if (audioFilePath != null) {
      final result = await transcribe(audio: audioFilePath, onToken: onToken);
      return CactusTranscriptionResult(text: result.text, isFinal: true);
    }
    final result =
        await transcribe(audio: audioStream ?? audio, onToken: onToken);
    return CactusTranscriptionResult(text: result.text, isFinal: true);
  }

  Future<void> streamTranscribeStart({
    CactusSTTStreamTranscribeStartOptions? options,
  }) async {
    await init();

    if (_context == null) {
      throw CactusException('Model not initialized');
    }

    _streamHandle = _context!.streamTranscribeStart(options: options);
    _isStreamTranscribing = true;
  }

  Future<CactusSTTStreamTranscribeProcessResult> streamTranscribeProcess({
    required List<int> audio,
  }) async {
    if (!_isStreamTranscribing || _streamHandle == null) {
      throw CactusException(
          'Stream transcription not started. Call streamTranscribeStart() first.');
    }

    return compute(_streamTranscribeProcessInIsolate, {
      'streamHandle': _streamHandle!,
      'pcmData': audio is Uint8List ? audio : Uint8List.fromList(audio),
    });
  }

  Future<CactusSTTStreamTranscribeStopResult> streamTranscribeStop() async {
    if (!_isStreamTranscribing || _streamHandle == null) {
      throw CactusException(
          'Stream transcription not started. Call streamTranscribeStart() first.');
    }

    try {
      return await compute(_streamTranscribeStopInIsolate, {
        'streamHandle': _streamHandle!,
      });
    } finally {
      _isStreamTranscribing = false;
      _streamHandle = null;
    }
  }

  /// Detect language via isolated FFI call.
  Future<CactusSTTDetectLanguageResult> detectLanguage({
    required dynamic audio,
    CactusSTTDetectLanguageOptions? options,
  }) async {
    await init();

    if (_context == null) {
      throw CactusException('Model not initialized');
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

    return CactusContext.detectLanguageAt(
      handleAddress: _context!.address,
      audioPath: audioFilePath,
      pcmData: pcmData,
      options: options,
    );
  }

  /// Audio embed via isolated FFI call.
  Future<CactusSTTAudioEmbedResult> audioEmbed({
    required String audioPath,
  }) async {
    await init();

    if (_context == null) {
      throw CactusException('Model not initialized');
    }

    return compute(_audioEmbedInIsolate, {
      'handle': _context!.address,
      'audioPath': audioPath,
    });
  }

  Future<void> stop() async {
    _context?.stop();
  }

  Future<void> reset() async {
    _context?.reset();
  }

  Future<void> destroy() async {
    if (!_isInitialized) return;
    await stop();
    if (_isStreamTranscribing) {
      try {
        await streamTranscribeStop();
      } catch (e) {
        debugPrint('Error stopping stream transcription during destroy: $e');
      }
    }
    _context?.destroy();
    _context = null;
    _streamHandle = null;
    _isInitialized = false;
  }

  Future<List<CactusModel>> getModels() async {
    final allModels = await HuggingFace.fetchModels();
    final sttModels = allModels
        .where((m) => m.capabilities.contains('transcription'))
        .toList();
    for (var m in sttModels) {
      m.isDownloaded = await DownloadService.modelExists(m.slug);
    }
    return sttModels;
  }

  String getModelName() => modelName(model, options);
}

CactusSTTStreamTranscribeProcessResult _streamTranscribeProcessInIsolate(
    Map<String, dynamic> params) {
  return CactusContext.streamTranscribeProcessWithHandle(
    params['streamHandle'] as int,
    params['pcmData'] as List<int>,
  );
}

CactusSTTStreamTranscribeStopResult _streamTranscribeStopInIsolate(
    Map<String, dynamic> params) {
  return CactusContext.streamTranscribeStopWithHandle(
    params['streamHandle'] as int,
  );
}

CactusSTTAudioEmbedResult _audioEmbedInIsolate(Map<String, dynamic> params) {
  return CactusContext.audioEmbedWithHandle(
    params['handle'] as int,
    params['audioPath'] as String,
  );
}
