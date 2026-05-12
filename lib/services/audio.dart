import 'dart:async';
import 'dart:typed_data';

import 'package:cactus/models/types.dart';
import 'package:cactus/src/services/context.dart';
import 'package:cactus/src/services/api/huggingface.dart';
import 'package:cactus/src/utils/models/download.dart';
import 'package:cactus/services/config.dart';
import 'package:path_provider/path_provider.dart';

class CactusAudio {
  CactusContext? _context;
  bool _isInitialized = false;
  bool _isDownloading = false;

  final String model;
  final CactusModelOptions options;

  static const String _defaultModel = 'silero-vad';
  static const _defaultQuantization = 'int8';

  final _handleLock = _AsyncLock();

  CactusAudio({String? model, CactusModelOptions? options})
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
    if (_isModelPath(model)) return;
    if (_isDownloading) throw CactusException('Already downloading');
    _isDownloading = true;
    try {
      if (await DownloadService.modelExists(getModelName())) return;

      final registry = await HuggingFace.getRegistry();
      final modelConfig = registry[model];
      if (modelConfig == null) {
        throw CactusException('Model $model not found in registry');
      }

      final quantInfo = modelConfig.quantization[options.quantization];
      if (quantInfo == null) {
        throw CactusException(
            'Model $model does not have ${options.quantization} quantization');
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
        folder: getModelName(),
      );

      final success =
          await DownloadService.downloadAndExtractModels([task], onProgress);
      if (!success) {
        throw CactusException(
            'Failed to download model $model from $downloadUrl');
      }
    } finally {
      _isDownloading = false;
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;

    String modelPath;
    if (_isModelPath(model)) {
      modelPath = model.replaceFirst('file://', '');
    } else {
      if (!await DownloadService.modelExists(getModelName())) {
        throw CactusException('Model not downloaded. Call download() first.');
      }
      modelPath = await _resolveModelPath();
    }

    final cacheLocation = (await getApplicationDocumentsDirectory()).path;
    CactusConfig.setTelemetryEnvironment(cacheLocation);

    _context = await CactusContext.initContext(
      modelPath: modelPath,
    );

    _isInitialized = true;
  }

  Future<CactusAudioVADResult> vad({
    required dynamic audio,
    CactusAudioVADOptions? options,
  }) async {
    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return _handleLock.synchronized(() async {
      String? audioFilePath;
      Uint8List? pcmData;
      if (audio is String) {
        audioFilePath = audio;
      } else if (audio is List<int>) {
        pcmData = Uint8List.fromList(audio);
      } else {
        throw ArgumentError(
            'audio must be a String (filepath) or List<int> (PCM data)');
      }

      return CactusContext.vadAt(
        handleAddress: _context!.handle.address,
        audioPath: audioFilePath,
        pcmData: pcmData,
        options: options,
      );
    });
  }

  Future<CactusAudioDiarizeResult> diarize({
    required dynamic audio,
    CactusAudioDiarizeOptions? options,
  }) async {
    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return _handleLock.synchronized(() async {
      String? audioFilePath;
      Uint8List? pcmData;
      if (audio is String) {
        audioFilePath = audio;
      } else if (audio is List<int>) {
        pcmData = Uint8List.fromList(audio);
      } else {
        throw ArgumentError(
            'audio must be a String (filepath) or List<int> (PCM data)');
      }

      return CactusContext.diarizeAt(
        handleAddress: _context!.handle.address,
        audioPath: audioFilePath,
        pcmData: pcmData,
        options: options,
      );
    });
  }

  Future<CactusAudioEmbedSpeakerResult> embedSpeaker({
    required dynamic audio,
    CactusAudioEmbedSpeakerOptions? options,
  }) async {
    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return _handleLock.synchronized(() async {
      String? audioFilePath;
      Uint8List? pcmData;
      if (audio is String) {
        audioFilePath = audio;
      } else if (audio is List<int>) {
        pcmData = Uint8List.fromList(audio);
      } else {
        throw ArgumentError(
            'audio must be a String (filepath) or List<int> (PCM data)');
      }

      return CactusContext.embedSpeakerAt(
        handleAddress: _context!.handle.address,
        audioPath: audioFilePath,
        pcmData: pcmData,
        options: options,
      );
    });
  }

  Future<void> destroy() async {
    if (!_isInitialized) return;
    _context?.destroy();
    _context = null;
    _isInitialized = false;
  }

  Future<List<CactusModel>> getModels() async {
    final registry = await HuggingFace.getRegistry();
    final audioModels = registry.values
        .where((m) =>
            m.capabilities.contains('vad') ||
            m.capabilities.contains('diarization') ||
            m.capabilities.contains('speaker-embed'))
        .toList();
    for (var m in audioModels) {
      m.isDownloaded = await DownloadService.modelExists(m.slug);
    }
    return audioModels;
  }

  String getModelName() =>
      '$model-${options.quantization}${options.pro ? '-pro' : ''}';

  bool _isModelPath(String m) => m.startsWith('/') || m.startsWith('file://');
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