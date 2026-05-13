import 'dart:async';
import 'dart:convert';

import 'package:cactus/models/types.dart';
import 'package:cactus/utils/async_lock.dart';
import 'package:cactus/utils/model_utils.dart';
import 'package:cactus/context.dart';
import 'package:cactus/services/api/huggingface.dart';
import 'package:cactus/utils/models/download.dart';
import 'package:cactus/services/config.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CactusLM {
  CactusContext? _context;
  bool _isInitialized = false;
  bool _isDownloading = false;
  bool _isGenerating = false;

  final String model;
  final String? corpusDir;
  final bool cacheIndex;
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

  Future<void> download({
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

    if (isModelPath(effectiveModel)) return;
    if (_isDownloading) throw CactusException('Already downloading');
    _isDownloading = true;
    try {
      if (await DownloadService.modelExists(modelName)) return;

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
      final task = DownloadTask(
        url: downloadUrl,
        filename: actualFilename,
        folder: modelName,
      );

      final success =
          await DownloadService.downloadAndExtractModels([task], onProgress);
      if (!success) {
        throw CactusException(
            'Failed to download model $effectiveModel from $downloadUrl');
      }
    } finally {
      _isDownloading = false;
    }
  }

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
      corpusDir: corpusDir,
      cacheIndex: cacheIndex,
    );

    _isInitialized = true;
  }

  Future<void> initializeModel({String? model, CactusInitParams? params}) =>
      init();

  void destroy() {
    _context?.destroy();
    _context = null;
    _isInitialized = false;
  }

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

  Future<CactusLMTokenizeResult> tokenize({required String text}) async {
    await init();
    if (_context == null) throw CactusException('Model not initialized');

    return compute(_tokenizeInIsolate, {
      'handle': _context!.address,
      'text': text,
    });
  }

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

  Future<CactusLMEmbedResult> generateEmbedding({
    required String text,
    bool normalize = false,
  }) =>
      embed(text: text, normalize: normalize);

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

  Future<void> stop() async {
    _context?.stop();
  }

  Future<void> reset() async {
    _context?.reset();
  }

  Future<List<CactusModel>> getModels() async {
    final registry = await HuggingFace.getRegistry();
    final models = registry.values.toList();
    for (var m in models) {
      m.isDownloaded = await DownloadService.modelExists(m.slug);
    }
    return models;
  }

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
