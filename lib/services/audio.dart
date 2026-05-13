import 'dart:async';
import 'dart:typed_data';

import 'package:cactus/models/types.dart';
import 'package:cactus/context.dart';
import 'package:cactus/services/api/huggingface.dart';
import 'package:cactus/utils/models/download.dart';
import 'package:cactus/utils/async_lock.dart';
import 'package:cactus/utils/model_utils.dart';
import 'package:cactus/services/config.dart';
import 'package:path_provider/path_provider.dart';

/// Service for audio processing including VAD, diarization, and speaker
/// embedding using on-device models.
class CactusAudio {
  CactusContext? _context;
  bool _isInitialized = false;
  bool _isDownloading = false;

  /// The model identifier or file path used by this instance.
  final String model;

  /// Quantization and model options (e.g. int8, pro).
  final CactusModelOptions options;

  static const String _defaultModel = 'silero-vad';
  static const _defaultQuantization = 'int8';

  final _handleLock = AsyncLock();

  /// Creates a [CactusAudio] instance.
  ///
  /// [model]: model identifier or file path. Defaults to `'silero-vad'`.
  /// [options]: quantization and pro settings for the model.
  CactusAudio({String? model, CactusModelOptions? options})
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

  /// Downloads the model from Hugging Face if not already cached.
  ///
  /// [onProgress]: optional callback invoked with download progress.
  /// Throws [CactusException] if a download is already in progress or the
  /// model is not found in the registry.
  Future<void> download({CactusProgressCallback? onProgress}) async {
    if (isModelPath(model)) return;
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

  /// Initializes the underlying native model context.
  ///
  /// Resolves the model path and calls [CactusContext.initContext]. If the
  /// model has not been downloaded yet this throws [CactusException].
  Future<void> init() async {
    if (_isInitialized) return;

    String modelPath;
    if (isModelPath(model)) {
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

  /// Runs voice activity detection on the provided audio.
  ///
  /// [audio]: file path (`String`) or raw PCM data (`List<int>`).
  /// [options]: optional VAD parameters.
  /// Returns a [CactusAudioVADResult] with detected speech segments.
  Future<CactusAudioVADResult> vad({
    required dynamic audio,
    CactusAudioVADOptions? options,
  }) async {
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

    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return _handleLock.synchronized(() async {
      return CactusContext.vadAt(
        handleAddress: _context!.address,
        audioPath: audioFilePath,
        pcmData: pcmData,
        options: options,
      );
    });
  }

  /// Runs speaker diarization on the provided audio.
  ///
  /// [audio]: file path (`String`) or raw PCM data (`List<int>`).
  /// [options]: optional diarization parameters.
  /// Returns a [CactusAudioDiarizeResult] with speaker segments.
  Future<CactusAudioDiarizeResult> diarize({
    required dynamic audio,
    CactusAudioDiarizeOptions? options,
  }) async {
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

    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return _handleLock.synchronized(() async {
      return CactusContext.diarizeAt(
        handleAddress: _context!.address,
        audioPath: audioFilePath,
        pcmData: pcmData,
        options: options,
      );
    });
  }

  /// Generates a speaker embedding from the provided audio.
  ///
  /// [audio]: file path (`String`) or raw PCM data (`List<int>`).
  /// [options]: optional embedding parameters.
  /// Returns a [CactusAudioEmbedSpeakerResult] containing the embedding.
  Future<CactusAudioEmbedSpeakerResult> embedSpeaker({
    required dynamic audio,
    CactusAudioEmbedSpeakerOptions? options,
  }) async {
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

    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return _handleLock.synchronized(() async {
      return CactusContext.embedSpeakerAt(
        handleAddress: _context!.address,
        audioPath: audioFilePath,
        pcmData: pcmData,
        options: options,
      );
    });
  }

  /// Destroys the native model context and resets initialization state.
  Future<void> destroy() async {
    if (!_isInitialized) return;
    _context?.destroy();
    _context = null;
    _isInitialized = false;
  }

  /// Stops any in-progress audio processing on the native context.
  Future<void> stop() async {
    _context?.stop();
  }

  /// Resets the native model context to its initial state.
  Future<void> reset() async {
    _context?.reset();
  }

  /// Lists all audio-capable models (VAD, diarization, speaker-embed) from
  /// the Hugging Face registry and checks their download status.
  ///
  /// Returns a list of [CactusModel] entries.
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

  /// Returns the full model name constructed from [model] and [options].
  String getModelName() => modelName(model, options);
}
