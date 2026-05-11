import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:math';

import 'package:cactus/models/types.dart';
import 'package:cactus/models/tools.dart';
import 'package:cactus/src/services/context.dart';
import 'package:cactus/src/services/api/huggingface.dart';
import 'package:cactus/src/utils/models/download.dart';
import 'package:cactus/services/config.dart';
import 'package:cactus/src/services/bindings.dart' as bindings;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CactusLM {
  int? _handle;
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
  static const int _defaultEmbedBufferSize = 2048;

  final _handleLock = _AsyncLock();

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
    if (_isModelPath(model)) return model.replaceFirst('file://', '');
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
        throw CactusException(
            'Model not downloaded. Call download() first.');
      }
      modelPath = await _resolveModelPath();
    }

    final cacheLocation = (await getApplicationDocumentsDirectory()).path;
    CactusConfig.setTelemetryEnvironment(cacheLocation);

    final result = await CactusContext.initContext(
      modelPath,
      null,
      corpusDir: corpusDir,
      cacheIndex: cacheIndex,
    );
    _handle = result.$1;

    if (_handle == null) {
      throw CactusException(
          'Failed to initialize model at $modelPath: ${result.$2}');
    }

    _isInitialized = true;
  }

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
        final currentHandle = _handle;
        if (currentHandle == null) {
          throw CactusException('Model not initialized');
        }

        final effectiveOptions = options ?? _defaultCompleteOptions;
        final quantization = int.tryParse(
                this.options.quantization.replaceFirst('int', '')) ??
            8;

        final cactusTools = _convertLMTools(tools);

        if (onToken != null) {
          return CactusContext.completionStream(
            currentHandle,
            messages,
            effectiveOptions,
            quantization,
            tools: cactusTools,
            onToken: onToken,
          );
        }

        return CactusContext.completion(
          currentHandle,
          messages,
          effectiveOptions,
          quantization,
          tools: cactusTools,
        );
      });
    } finally {
      _isGenerating = false;
    }
  }

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
        final currentHandle = _handle;
        if (currentHandle == null) {
          throw CactusException('Model not initialized');
        }

        final effectiveOptions = options ?? _defaultCompleteOptions;
        final quantization = int.tryParse(
                this.options.quantization.replaceFirst('int', '')) ??
            8;

        final cactusTools = _convertLMTools(tools);

        return CactusContext.prefill(
          currentHandle,
          messages,
          effectiveOptions,
          tools: cactusTools,
          pcmData: audio,
          quantization: quantization,
        );
      });
    } finally {
      _isGenerating = false;
    }
  }

  Future<CactusLMTokenizeResult> tokenize({required String text}) async {
    await init();
    final currentHandle = _handle;
    if (currentHandle == null) throw CactusException('Model not initialized');

    return compute(_tokenizeInIsolate, {
      'handle': currentHandle,
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
    final currentHandle = _handle;
    if (currentHandle == null) throw CactusException('Model not initialized');

    return compute(_scoreWindowInIsolate, {
      'handle': currentHandle,
      'tokens': tokens,
      'start': start,
      'end': end,
      'context': context,
    });
  }

  Future<CactusLMEmbedResult> embed({
    required String text,
    bool normalize = false,
  }) async {
    if (_isGenerating) throw CactusException('Already generating');
    await init();

    return _handleLock.synchronized(() async {
      final currentHandle = _handle;
      if (currentHandle == null) throw CactusException('Model not initialized');

      return CactusContext.generateEmbedding(
          currentHandle, text, _defaultEmbedBufferSize);
    });
  }

  Future<CactusLMImageEmbedResult> imageEmbed({
    required String imagePath,
  }) async {
    if (_isGenerating) throw CactusException('Already generating');
    await init();

    return _handleLock.synchronized(() async {
      final currentHandle = _handle;
      if (currentHandle == null) throw CactusException('Model not initialized');

      return compute(_imageEmbedInIsolate, {
        'handle': currentHandle,
        'imagePath': imagePath,
        'bufferSize': _defaultEmbedBufferSize,
      });
    });
  }

  Future<CactusLMRagQueryResult> ragQuery({
    required String query,
    int topK = 5,
  }) async {
    await init();
    final currentHandle = _handle;
    if (currentHandle == null) throw CactusException('Model not initialized');

    return compute(_ragQueryInIsolate, {
      'handle': currentHandle,
      'query': query,
      'topK': topK,
      'bufferSize': 8192,
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
    final currentHandle = _handle;
    if (currentHandle != null) {
      CactusContext.freeContext(currentHandle);
    }
    _handle = null;
    _isInitialized = false;
  }

  Future<List<CactusModel>> getModels() async {
    final registry = await HuggingFace.getRegistry();
    final models = registry.values.toList();
    for (var m in models) {
      m.isDownloaded = await DownloadService.modelExists(m.slug);
    }
    return models;
  }

  String getModelName() =>
      '$model-${options.quantization}${options.pro ? '-pro' : ''}';

  bool _isModelPath(String m) =>
      m.startsWith('/') || m.startsWith('file://');
}

CactusLMTokenizeResult _tokenizeInIsolate(Map<String, dynamic> params) {
  final handle = params['handle'] as int;
  final text = params['text'] as String;

  final textC = text.toNativeUtf8(allocator: calloc);
  final tokenBufferLen = max(text.length * 2, 1024);
  final tokenBuffer = calloc<Uint32>(tokenBufferLen);
  final outTokenLen = calloc<IntPtr>();

  try {
    final result = bindings.cactusTokenize(
      Pointer.fromAddress(handle),
      textC,
      tokenBuffer,
      tokenBufferLen,
      outTokenLen,
    );

    if (result > 0 || outTokenLen.value > 0) {
      final count = outTokenLen.value;
      final tokens = <int>[];
      for (int i = 0; i < count && i < tokenBufferLen; i++) {
        tokens.add(tokenBuffer[i]);
      }
      return CactusLMTokenizeResult(tokens: tokens);
    }

    return CactusLMTokenizeResult(tokens: []);
  } finally {
    calloc.free(textC);
    calloc.free(tokenBuffer);
    calloc.free(outTokenLen);
  }
}

CactusLMScoreWindowResult _scoreWindowInIsolate(Map<String, dynamic> params) {
  final handle = params['handle'] as int;
  final tokens = params['tokens'] as List<int>;
  final start = params['start'] as int;
  final end = params['end'] as int;
  final context = params['context'] as int;

  final tokenPtr = calloc<Uint32>(tokens.length);
  final responseBuffer = calloc<Uint8>(4096);

  try {
    for (int i = 0; i < tokens.length; i++) {
      tokenPtr[i] = tokens[i];
    }

    final result = bindings.cactusScoreWindow(
      Pointer.fromAddress(handle),
      tokenPtr,
      tokens.length,
      start,
      end,
      context,
      responseBuffer.cast<Utf8>(),
      4096,
    );

    if (result > 0) {
      final responseText = utf8
          .decode(responseBuffer.asTypedList(result), allowMalformed: true)
          .trim();
      try {
        final json = jsonDecode(responseText) as Map<String, dynamic>;
        return CactusLMScoreWindowResult(
          score: (json['score'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (_) {
        return CactusLMScoreWindowResult(score: 0.0);
      }
    }

    return CactusLMScoreWindowResult(score: 0.0);
  } finally {
    calloc.free(tokenPtr);
    calloc.free(responseBuffer);
  }
}

CactusLMImageEmbedResult _imageEmbedInIsolate(Map<String, dynamic> params) {
  final handle = params['handle'] as int;
  final imagePath = params['imagePath'] as String;
  final bufferSize = params['bufferSize'] as int;

  final imagePathC = imagePath.toNativeUtf8(allocator: calloc);
  final embeddingDimPtr = calloc<IntPtr>();
  final embeddingsBuffer = calloc<Float>(bufferSize);

  try {
    final result = bindings.cactusImageEmbed(
      Pointer.fromAddress(handle),
      imagePathC,
      embeddingsBuffer,
      bufferSize * 4,
      embeddingDimPtr,
    );

    if (result > 0) {
      final actualDim = embeddingDimPtr.value;
      if (actualDim > bufferSize) {
        return CactusLMImageEmbedResult(embedding: []);
      }
      final embedding = <double>[];
      for (int i = 0; i < actualDim; i++) {
        embedding.add(embeddingsBuffer[i]);
      }
      return CactusLMImageEmbedResult(embedding: embedding);
    }

    return CactusLMImageEmbedResult(embedding: []);
  } finally {
    calloc.free(imagePathC);
    calloc.free(embeddingDimPtr);
    calloc.free(embeddingsBuffer);
  }
}

CactusLMRagQueryResult _ragQueryInIsolate(Map<String, dynamic> params) {
  final handle = params['handle'] as int;
  final query = params['query'] as String;
  final topK = params['topK'] as int;
  final bufferSize = params['bufferSize'] as int;

  final queryC = query.toNativeUtf8(allocator: calloc);
  final responseBuffer = calloc<Uint8>(bufferSize);

  try {
    final result = bindings.cactusRagQuery(
      Pointer.fromAddress(handle),
      queryC,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      topK,
    );

    if (result > 0) {
      final responseText = utf8
          .decode(responseBuffer.asTypedList(result), allowMalformed: true)
          .trim();
      try {
        final json = jsonDecode(responseText) as Map<String, dynamic>;
        final chunksJson = json['chunks'] as List<dynamic>? ?? [];
        final chunks = chunksJson.map((c) {
          final cMap = c as Map<String, dynamic>;
          return RagQueryChunk(
            score: (cMap['score'] as num?)?.toDouble() ?? 0.0,
            source: cMap['source'] as String? ?? '',
            content: cMap['content'] as String? ?? '',
          );
        }).toList();
        return CactusLMRagQueryResult(chunks: chunks);
      } catch (e) {
        return CactusLMRagQueryResult(error: 'Failed to parse RAG response: $e');
      }
    }

    return CactusLMRagQueryResult(error: 'RAG query failed');
  } finally {
    calloc.free(queryC);
    calloc.free(responseBuffer);
  }
}

List<CactusTool>? _convertLMTools(List<CactusLMTool>? tools) {
  return tools?.map((t) => CactusTool(
    name: t.name,
    description: t.description,
    parameters: ToolParametersSchema.fromJson(t.parameters),
  )).toList();
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
