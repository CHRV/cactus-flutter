import 'dart:async';

import 'package:cactus/models/types.dart';
import 'package:cactus/context.dart';
import 'package:cactus/services/api/huggingface.dart';
import 'package:cactus/utils/models/download.dart';
import 'package:cactus/utils/models/download_state.dart';
import 'package:cactus/utils/async_lock.dart';
import 'package:cactus/utils/model_utils.dart';
import 'package:cactus/services/config.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Speech-to-text service wrapping a Cactus context for transcription,
/// language detection, and audio embedding.
class CactusSTT {
  CactusContext? _context;
  int? _streamHandle;
  bool _isInitialized = false;
  bool _isDownloading = false;
  bool _isStreamTranscribing = false;
  DownloadHandle? _currentDownload;

  /// The name of the model (e.g. `whisper-small`).
  final String model;

  /// Quantization and pro options for the model.
  final CactusModelOptions options;

  static const String _defaultModel = 'whisper-small';
  static const _defaultQuantization = 'int8';

  /// Default transcription prompt that enables English transcription without
  /// timestamps.
  static const String defaultPrompt =
      '<|startoftranscript|><|en|><|transcribe|><|notimestamps|>';
  static const _defaultTranscribeOptions =
      CactusSTTTranscribeOptions(maxTokens: 384);

  final _handleLock = AsyncLock();

  /// Creates a [CactusSTT] instance.
  ///
  /// [model]: Model identifier (defaults to `whisper-small`).
  /// [options]: Quantization and pro options.
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

  /// Downloads the model from Hugging Face.
  ///
  /// Returns a [DownloadHandle] for pause / resume / cancel control.
  /// [model]: Override model name. Defaults to the instance model.
  /// [onProgress]: Callback for download progress.
  Future<DownloadHandle> download({
    String? model,
    CactusProgressCallback? onProgress,
  }) async {
    if (_isDownloading) throw CactusException('Already downloading');
    _isDownloading = true;
    try {
      final effectiveModel = model ?? this.model;
      final modelName =
          '$effectiveModel-${options.quantization}${options.pro ? '-pro' : ''}';
      if (await ResumableDownloadService.modelExists(modelName)) {
        throw CactusException('Model already downloaded');
      }

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
      final handle = await ResumableDownloadService.download(
        url: downloadUrl,
        filename: actualFilename,
        folder: modelName,
        onProgress: (dp) {
          onProgress?.call(
              dp.progress, dp.statusMessage, dp.errorMessage != null);
          if (dp.status == DownloadStatus.completed ||
              dp.status == DownloadStatus.failed ||
              dp.status == DownloadStatus.cancelled) {
            _isDownloading = false;
            _currentDownload = null;
          }
        },
      );
      _currentDownload = handle;
      return handle;
    } catch (e) {
      _isDownloading = false;
      rethrow;
    }
  }

  /// Cancels the current download, if any.
  void cancelDownload() {
    _currentDownload?.cancel();
    _currentDownload = null;
    _isDownloading = false;
  }

  /// Initializes the Cactus context and loads the model.
  ///
  /// Downloads the model first if it is not present locally.
  Future<void> init() async {
    if (_isInitialized) return;

    final modelPath = await _resolveModelPath();
    final cacheLocation = (await getApplicationDocumentsDirectory()).path;
    CactusConfig.setTelemetryEnvironment(cacheLocation);

    _context = await CactusContext.initContext(
      modelPath: modelPath,
    );

    if (_context == null &&
        !await ResumableDownloadService.modelExists(getModelName())) {
      debugPrint('Failed to initialize model at $modelPath, downloading...');
      await download();
      return init();
    }

    if (_context == null) {
      throw CactusException('Failed to initialize model at $modelPath');
    }

    _isInitialized = true;
  }

  /// Initializes the model with optional custom parameters. Delegates to
  /// [init].
  ///
  /// [model]: Override model name.
  /// [params]: Optional initialization parameters.
  Future<void> initializeModel({String? model, CactusInitParams? params}) =>
      init();

  /// Downloads a specific model. Delegates to [download].
  ///
  /// [model]: Model identifier (required).
  /// [quantization]: Quantization override.
  /// [pro]: Whether to use the pro variant.
  /// [onProgress]: Callback for download progress.
  Future<void> downloadModel({
    required String model,
    String? quantization,
    bool pro = false,
    CactusProgressCallback? onProgress,
  }) =>
      download(onProgress: onProgress);

  /// Unloads the model and releases the context.
  void unload() {
    _context?.destroy();
    _context = null;
    _isInitialized = false;
  }

  /// Returns available voice (transcription) models from the registry.
  Future<List<VoiceModel>> getVoiceModels() async {
    final registry = await HuggingFace.getRegistry();
    return registry.values
        .where((m) => m.capabilities.contains('transcription'))
        .toList();
  }

  /// Transcribes audio via an isolated FFI call.
  ///
  /// [audio]: File path (`String`) or raw PCM data (`List<int>`).
  /// [prompt]: Optional transcription prompt.
  /// [options]: Transcription options (e.g. max tokens).
  /// [onToken]: Callback invoked for each transcribed token.
  /// Returns: Transcription result containing the recognized text.
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

  /// Transcribes audio and returns a final result.
  ///
  /// [audio]: Raw PCM data.
  /// [audioStream]: Alternative PCM data for streaming.
  /// [audioFilePath]: Path to an audio file on disk.
  /// [onToken]: Callback invoked for each transcribed token.
  /// Returns: A transcription result marked as final.
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

  /// Starts a streaming transcription session.
  ///
  /// Must be called before [streamTranscribeProcess].
  /// [options]: Stream start options.
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

  /// Processes a chunk of audio in an ongoing streaming transcription.
  ///
  /// [audio]: Raw PCM audio chunk.
  /// Returns: Partial transcription result.
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

  /// Stops the active streaming transcription and returns the final result.
  ///
  /// Returns: Final transcription result.
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

  /// Detects the language of the provided audio.
  ///
  /// [audio]: File path (`String`) or raw PCM data (`List<int>`).
  /// [options]: Language detection options.
  /// Returns: Language detection result.
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

  /// Generates an audio embedding for the given audio file.
  ///
  /// [audioPath]: Path to the audio file.
  /// Returns: Audio embedding result.
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

  /// Stops the current transcription or detection operation.
  Future<void> stop() async {
    _context?.stop();
  }

  /// Resets the model state.
  Future<void> reset() async {
    _context?.reset();
  }

  /// Destroys the context and cleans up all resources.
  ///
  /// Stops any active operation and streaming transcription before releasing
  /// the model.
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

  /// Fetches all available STT models from Hugging Face and marks which are
  /// downloaded locally.
  ///
  /// Returns: List of available STT models.
  Future<List<CactusModel>> getModels() async {
    final allModels = await HuggingFace.fetchModels();
    final sttModels = allModels
        .where((m) => m.capabilities.contains('transcription'))
        .toList();
    for (var m in sttModels) {
      m.isDownloaded = await ResumableDownloadService.modelExists(m.slug);
    }
    return sttModels;
  }

  /// Returns the full model name (slug) derived from [model] and [options].
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
