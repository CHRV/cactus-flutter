import 'dart:async';
import 'dart:convert';

import 'package:cactus/models/types.dart';
import 'package:cactus/utils/async_lock.dart';
import 'package:cactus/utils/model_utils.dart';
import 'package:cactus/context.dart';
import 'package:cactus/services/api/huggingface.dart';
import 'package:cactus/utils/models/download.dart';
import 'package:cactus/utils/models/download_state.dart';
import 'package:cactus/services/config.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// High-level interface to a Cactus language model.
///
/// Manages model download, initialization, inference (completion, embedding,
/// RAG), and resource lifecycle.
class CactusLM {
  CactusContext? _context;
  bool _isInitialized = false;
  bool _isDownloading = false;
  bool _isGenerating = false;
  DownloadHandle? _currentDownload;

  /// The model identifier (e.g. "qwen3-0.6b").
  final String model;

  /// Optional directory for retrieval-augmented generation (RAG) corpus files.
  final String? corpusDir;

  /// Whether to cache the RAG index on disk.
  final bool cacheIndex;

  /// Configuration options such as quantization level and pro mode.
  final CactusModelOptions options;

  static const String _defaultModel = 'qwen3-0.6b';
  static const _defaultQuantization = 'int8';
  static const _quantizationExceptions = <String, String>{
    'gemma-3-270m-it': 'int8',
    'functiongemma-270m-it': 'int8',
  };
  static const _defaultCompleteOptions =
      CactusLMCompleteOptions(maxTokens: 512);

  final _handleLock = AsyncLock();

  /// Creates a [CactusLM] instance.
  ///
  /// [model]: Model identifier. Defaults to [_defaultModel].
  /// [corpusDir]: Optional directory for RAG corpus files.
  /// [cacheIndex]: Whether to cache the RAG index on disk. Defaults to false.
  /// [options]: Optional configuration overrides (quantization, pro mode).
  CactusLM({
    String? model,
    this.corpusDir,
    bool? cacheIndex,
    CactusModelOptions? options,
  })  : model = model ?? _defaultModel,
        cacheIndex = cacheIndex ?? false,
        options = CactusModelOptions(
          quantization: options?.quantization ??
              _quantizationExceptions[model ?? _defaultModel] ??
              _defaultQuantization,
          pro: options?.pro ?? false,
        );

  Future<String> _resolveModelPath() async {
    if (isModelPath(model)) return model.replaceFirst('file://', '');
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models/${modelName(model, options)}';
  }

  /// Downloads the model from HuggingFace if not already present locally.
  ///
  /// Returns a [DownloadHandle] for pause / resume / cancel control.
  /// [model]: Override model identifier. Uses instance [model] if null.
  /// [quantization]: Override quantization level.
  /// [pro]: Whether to use the pro (Apple) variant.
  /// [onProgress]: Callback invoked with download progress updates.
  ///
  /// Throws [CactusException] if a download is already in progress or the
  /// model is not found in the registry.
  Future<DownloadHandle> download({
    String? model,
    String? quantization,
    bool? pro,
    CactusProgressCallback? onProgress,
  }) async {
    final effectiveModel = model ?? this.model;
    final effectiveQuant = quantization ?? options.quantization;
    final effectivePro = pro ?? options.pro;

    final modelName = effectivePro
        ? '$effectiveModel-$effectiveQuant-pro'
        : '$effectiveModel-$effectiveQuant';

    if (isModelPath(effectiveModel)) throw CactusException('Cannot download file:// paths');
    if (_isDownloading) throw CactusException('Already downloading');
    _isDownloading = true;

    try {
      if (await ResumableDownloadService.modelExists(modelName)) {
        throw CactusException('Model already downloaded');
      }

      final registry = await HuggingFace.getRegistry();
      final modelConfig = registry[effectiveModel];
      if (modelConfig == null) {
        throw CactusException('Model $effectiveModel not found in registry');
      }

      final quantInfo = modelConfig.quantization[effectiveQuant];
      if (quantInfo == null) {
        throw CactusException(
            'Model $effectiveModel does not have $effectiveQuant quantization');
      }

      String downloadUrl;
      if (effectivePro && quantInfo.pro != null) {
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
          if (dp.status == DownloadStatus.completed) {
            _isDownloading = false;
            _currentDownload = null;
          } else if (dp.status == DownloadStatus.failed ||
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

  /// Initializes the model context and loads the model into memory.
  ///
  /// Resolves the model path from a local file or the application documents
  /// directory. Throws [CactusException] if the model has not been downloaded.
  Future<void> init() async {
    if (_isInitialized) return;

    String modelPath;
    if (isModelPath(model)) {
      modelPath = model.replaceFirst('file://', '');
    } else {
      if (!await ResumableDownloadService.modelExists(getModelName())) {
        throw CactusException('Model not downloaded. Call download() first.');
      }
      modelPath = await _resolveModelPath();
    }

    final cacheLocation = (await getApplicationDocumentsDirectory()).path;
    CactusConfig.setTelemetryEnvironment(cacheLocation);

    _context = await CactusContext.initContext(
      modelPath: modelPath,
      corpusDir: corpusDir,
      cacheIndex: cacheIndex,
    );

    _isInitialized = true;
  }

  /// Initializes or re-initializes the model.
  ///
  /// [model]: Optional model identifier override.
  /// [params]: Optional initialization parameters.
  Future<void> initializeModel({String? model, CactusInitParams? params}) =>
      init();

  /// Destroys the model context and releases all associated resources.
  void destroy() {
    _context?.destroy();
    _context = null;
    _isInitialized = false;
  }

  /// Alias for [destroy]. Unloads the model from memory.
  void unload() => destroy();

  /// Complete via isolated FFI call. Uses Isolate.spawn because
  /// cactusComplete streams tokens through a Dart callback.
  Future<CactusLMCompleteResult> complete({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    CactusTokenCallback? onToken,
    List<int>? audio,
  }) async {
    if (_isGenerating) throw CactusException('Already generating');
    await init();
    _isGenerating = true;

    try {
      return _handleLock.synchronized(() async {
        if (_context == null) {
          throw CactusException('Model not initialized');
        }

        final effectiveOptions = options ?? _defaultCompleteOptions;
        final messagesJson =
            jsonEncode(messages.map((m) => m.toJson()).toList());
        final optionsJson = jsonEncode(effectiveOptions.toJson());
        final toolsJson =
            jsonEncode(tools?.map((t) => t.toJson()).toList() ?? []);

        return CactusContext.completeAt(
          handleAddress: _context!.address,
          messagesJson: messagesJson,
          optionsJson: optionsJson,
          toolsJson: toolsJson,
          onToken: onToken,
          pcmData: audio != null ? Uint8List.fromList(audio) : null,
        );
      });
    } finally {
      _isGenerating = false;
    }
  }

  /// Generates a completion for the given conversation messages.
  ///
  /// [messages]: The conversation messages to complete.
  /// [params]: Optional completion parameters (e.g. max tokens, temperature).
  /// [tools]: Optional tool definitions for function calling.
  /// [onToken]: Callback invoked for each generated token.
  /// [audio]: Optional PCM audio data for audio-capable models.
  ///
  /// Returns the full [CactusLMCompleteResult].
  Future<CactusLMCompleteResult> generateCompletion({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? params,
    List<CactusLMTool>? tools,
    CactusTokenCallback? onToken,
    List<int>? audio,
  }) =>
      complete(
        messages: messages,
        options: params,
        tools: tools,
        onToken: onToken,
        audio: audio,
      );

  /// Generates a streaming completion, yielding tokens via a [Stream].
  ///
  /// [messages]: The conversation messages to complete.
  /// [params]: Optional completion parameters.
  /// [tools]: Optional tool definitions for function calling.
  /// [audio]: Optional PCM audio data for audio-capable models.
  ///
  /// Returns a [CactusStreamedCompletionResult] containing both a token stream
  /// and a future that resolves to the full [CactusLMCompleteResult].
  Future<CactusStreamedCompletionResult> generateCompletionStream({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? params,
    List<CactusLMTool>? tools,
    List<int>? audio,
  }) async {
    final controller = StreamController<String>();
    final resultFuture = complete(
      messages: messages,
      options: params,
      tools: tools,
      onToken: (token) => controller.add(token),
      audio: audio,
    ).then((res) {
      controller.close();
      return res;
    });

    return CactusStreamedCompletionResult(
      stream: controller.stream,
      result: resultFuture,
    );
  }

  /// Prefill via isolated FFI call.
  Future<CactusLMPrefillResult> prefill({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    List<int>? audio,
  }) async {
    if (_isGenerating) throw CactusException('Already generating');
    await init();
    _isGenerating = true;

    try {
      return _handleLock.synchronized(() async {
        if (_context == null) {
          throw CactusException('Model not initialized');
        }

        final effectiveOptions = options ?? _defaultCompleteOptions;
        final messagesJson =
            jsonEncode(messages.map((m) => m.toJson()).toList());
        final optionsJson = jsonEncode(effectiveOptions.toJson());
        final toolsJson =
            jsonEncode(tools?.map((t) => t.toJson()).toList() ?? []);

        return CactusContext.prefillAt(
          handleAddress: _context!.address,
          messagesJson: messagesJson,
          optionsJson: optionsJson,
          toolsJson: toolsJson,
          pcmData: audio != null ? Uint8List.fromList(audio) : null,
        );
      });
    } finally {
      _isGenerating = false;
    }
  }

  /// Tokenizes the input text into token IDs using the loaded model.
  ///
  /// [text]: The input string to tokenize.
  ///
  /// Returns a [CactusLMTokenizeResult] containing the token IDs.
  Future<CactusLMTokenizeResult> tokenize({required String text}) async {
    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return compute(_tokenizeInIsolate, {
      'handle': _context!.address,
      'text': text,
    });
  }

  /// Scores a window of tokens, computing log-probabilities.
  ///
  /// [tokens]: The full token sequence.
  /// [start]: Start index of the scoring window.
  /// [end]: End index of the scoring window (exclusive).
  /// [context]: Number of context tokens preceding the window.
  ///
  /// Returns a [CactusLMScoreWindowResult] with per-token scores.
  Future<CactusLMScoreWindowResult> scoreWindow({
    required List<int> tokens,
    required int start,
    required int end,
    required int context,
  }) async {
    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return compute(_scoreWindowInIsolate, {
      'handle': _context!.address,
      'tokens': tokens,
      'start': start,
      'end': end,
      'context': context,
    });
  }

  /// Embed via isolated FFI call.
  Future<CactusLMEmbedResult> embed({
    required String text,
    bool normalize = false,
  }) async {
    if (_isGenerating) throw CactusException('Already generating');
    await init();

    return _handleLock.synchronized(() async {
      if (_context == null) throw CactusException('Model not initialized');

      return compute(_embedInIsolate, {
        'handle': _context!.address,
        'text': text,
        'normalize': normalize,
      });
    });
  }

  /// Generates an embedding vector for the given text.
  ///
  /// [text]: The input text to embed.
  /// [normalize]: Whether to L2-normalize the embedding vector. Defaults to false.
  ///
  /// Returns a [CactusLMEmbedResult] containing the embedding.
  Future<CactusLMEmbedResult> generateEmbedding({
    required String text,
    bool normalize = false,
  }) =>
      embed(text: text, normalize: normalize);

  /// Generates an embedding for the image at the given file path.
  ///
  /// [imagePath]: Absolute or relative path to the image file.
  ///
  /// Returns a [CactusLMImageEmbedResult] containing the image embedding.
  Future<CactusLMImageEmbedResult> imageEmbed({
    required String imagePath,
  }) async {
    if (_isGenerating) throw CactusException('Already generating');
    await init();

    return _handleLock.synchronized(() async {
      if (_context == null) throw CactusException('Model not initialized');

      return compute(_imageEmbedInIsolate, {
        'handle': _context!.address,
        'imagePath': imagePath,
      });
    });
  }

  /// Queries the RAG corpus for context relevant to the given query.
  ///
  /// [query]: The search query string.
  /// [topK]: Number of top results to return. Defaults to 5.
  ///
  /// Returns a [CactusLMRagQueryResult] with ranked matches.
  Future<CactusLMRagQueryResult> ragQuery({
    required String query,
    int topK = 5,
  }) async {
    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return compute(_ragQueryInIsolate, {
      'handle': _context!.address,
      'query': query,
      'topK': topK,
    });
  }

  /// Stops the current generation in progress.
  Future<void> stop() async {
    _context?.stop();
  }

  /// Resets the model state, clearing the internal context cache.
  Future<void> reset() async {
    _context?.reset();
  }

  /// Retrieves available models from the HuggingFace registry.
  ///
  /// Checks and annotates the download status for each model.
  ///
  /// Returns a list of [CactusModel] entries.
  Future<List<CactusModel>> getModels() async {
    final registry = await HuggingFace.getRegistry();
    final models = registry.values.toList();
    for (var m in models) {
      m.isDownloaded = await ResumableDownloadService.modelExists(m.slug);
    }
    return models;
  }

  /// Returns the resolved model name including quantization and pro suffix.
  String getModelName() => modelName(model, options);
}

CactusLMTokenizeResult _tokenizeInIsolate(Map<String, dynamic> params) {
  return CactusContext.tokenizeWithHandle(
    params['handle'] as int,
    params['text'] as String,
  );
}

CactusLMScoreWindowResult _scoreWindowInIsolate(Map<String, dynamic> params) {
  return CactusContext.scoreWindowWithHandle(
    params['handle'] as int,
    params['tokens'] as List<int>,
    params['start'] as int,
    params['end'] as int,
    params['context'] as int,
  );
}

CactusLMEmbedResult _embedInIsolate(Map<String, dynamic> params) {
  return CactusContext.embedWithHandle(
    params['handle'] as int,
    params['text'] as String,
    params['normalize'] as bool,
  );
}

CactusLMImageEmbedResult _imageEmbedInIsolate(Map<String, dynamic> params) {
  return CactusContext.imageEmbedWithHandle(
    params['handle'] as int,
    params['imagePath'] as String,
  );
}

CactusLMRagQueryResult _ragQueryInIsolate(Map<String, dynamic> params) {
  return CactusContext.ragQueryWithHandle(
    params['handle'] as int,
    params['query'] as String,
    params['topK'] as int,
  );
}
