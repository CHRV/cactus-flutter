import 'dart:convert';
import 'dart:ffi';

import 'package:cactus/models/types.dart';
import 'package:cactus/src/services/bindings.dart' as bindings;
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

class CactusIndex {
  int? _handle;
  bool _isInitialized = false;

  final String name;
  final int embeddingDim;

  CactusIndex({
    required this.name,
    required this.embeddingDim,
  });

  Future<void> init() async {
    if (_isInitialized) return;

    final dir = await getApplicationDocumentsDirectory();
    final indexDir = '${dir.path}/indices/$name';

    final indexDirC = indexDir.toNativeUtf8(allocator: calloc);
    try {
      final handle = bindings.cactusIndexInit(indexDirC, embeddingDim);
      if (handle == nullptr) {
        throw CactusException('Failed to initialize index at $indexDir');
      }
      _handle = handle.address;
      _isInitialized = true;
    } finally {
      calloc.free(indexDirC);
    }
  }

  Future<void> add({
    required List<int> ids,
    required List<String> documents,
    required List<List<double>> embeddings,
    List<String>? metadatas,
  }) async {
    await _ensureInitialized();
    final count = ids.length;
    final dim = embeddingDim;

    final idsPtr = calloc<Int32>(count);
    final docPtrs = calloc<Pointer<Utf8>>(count);
    final metaPtrs = calloc<Pointer<Utf8>>(count);
    final embPtrs = calloc<Pointer<Float>>(count);

    try {
      for (int i = 0; i < count; i++) {
        idsPtr[i] = ids[i];
        docPtrs[i] = documents[i].toNativeUtf8(allocator: calloc);
        metaPtrs[i] = (metadatas != null && i < metadatas.length)
            ? metadatas[i].toNativeUtf8(allocator: calloc)
            : nullptr;

        final embPtr = calloc<Float>(dim);
        for (int j = 0; j < dim && j < embeddings[i].length; j++) {
          embPtr[j] = embeddings[i][j];
        }
        embPtrs[i] = embPtr;
      }

      final result = bindings.cactusIndexAdd(
        Pointer.fromAddress(_handle!),
        idsPtr,
        docPtrs,
        metaPtrs,
        embPtrs,
        count,
        dim,
      );

      if (result <= 0) {
        throw CactusException('Failed to add entries to index');
      }
    } finally {
      for (int i = 0; i < count; i++) {
        if (docPtrs[i] != nullptr) calloc.free(docPtrs[i]);
        if (metaPtrs[i] != nullptr) calloc.free(metaPtrs[i]);
        if (embPtrs[i] != nullptr) calloc.free(embPtrs[i]);
      }
      calloc.free(idsPtr);
      calloc.free(docPtrs);
      calloc.free(metaPtrs);
      calloc.free(embPtrs);
    }
  }

  Future<void> delete({required List<int> ids}) async {
    await _ensureInitialized();
    final count = ids.length;
    final idsPtr = calloc<Int32>(count);

    try {
      for (int i = 0; i < count; i++) {
        idsPtr[i] = ids[i];
      }

      final result = bindings.cactusIndexDelete(
        Pointer.fromAddress(_handle!),
        idsPtr,
        count,
      );

      if (result <= 0) {
        throw CactusException('Failed to delete entries from index');
      }
    } finally {
      calloc.free(idsPtr);
    }
  }

  Future<CactusIndexGetResult> get({required List<int> ids}) async {
    await _ensureInitialized();
    final count = ids.length;

    final idsPtr = calloc<Int32>(count);
    final docBuffers = calloc<Pointer<Utf8>>(count);
    final docSizes = calloc<IntPtr>(count);
    final metaBuffers = calloc<Pointer<Utf8>>(count);
    final metaSizes = calloc<IntPtr>(count);
    final embBuffers = calloc<Pointer<Float>>(count);
    final embSizes = calloc<IntPtr>(count);

    try {
      for (int i = 0; i < count; i++) {
        idsPtr[i] = ids[i];
      }

      final result = bindings.cactusIndexGet(
        Pointer.fromAddress(_handle!),
        idsPtr,
        count,
        docBuffers,
        docSizes,
        metaBuffers,
        metaSizes,
        embBuffers,
        embSizes,
      );

      if (result <= 0) {
        return CactusIndexGetResult();
      }

      final documents = <String>[];
      final metadatas = <String>[];
      final embeddings = <List<double>>[];

      for (int i = 0; i < count; i++) {
        if (docBuffers[i] != nullptr && docSizes[i] > 0) {
          documents.add(docBuffers[i].toDartString(length: docSizes[i]));
        } else {
          documents.add('');
        }

        if (metaBuffers[i] != nullptr && metaSizes[i] > 0) {
          metadatas.add(metaBuffers[i].toDartString(length: metaSizes[i]));
        } else {
          metadatas.add('');
        }

        final embSize = embSizes[i];
        final emb = <double>[];
        if (embBuffers[i] != nullptr && embSize > 0) {
          for (int j = 0; j < embSize; j++) {
            emb.add(embBuffers[i][j]);
          }
        }
        embeddings.add(emb);
      }

      return CactusIndexGetResult(
        documents: documents,
        metadatas: metadatas,
        embeddings: embeddings,
      );
    } finally {
      calloc.free(idsPtr);
      calloc.free(docBuffers);
      calloc.free(docSizes);
      calloc.free(metaBuffers);
      calloc.free(metaSizes);
      calloc.free(embBuffers);
      calloc.free(embSizes);
    }
  }

  Future<CactusIndexQueryResult> query({
    required List<List<double>> embeddings,
    CactusIndexQueryOptions? options,
  }) async {
    await _ensureInitialized();
    final embCount = embeddings.length;
    final dim = embeddingDim;

    final embPtrs = calloc<Pointer<Float>>(embCount);
    final optionsMap = <String, dynamic>{};
    if (options?.topK != null) optionsMap['top_k'] = options!.topK;
    if (options?.scoreThreshold != null) {
      optionsMap['score_threshold'] = options!.scoreThreshold;
    }
    final optionsJson = jsonEncode(optionsMap);
    final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);

    final idBuffers = calloc<Pointer<Int32>>(embCount);
    final idSizes = calloc<IntPtr>(embCount);
    final scoreBuffers = calloc<Pointer<Float>>(embCount);
    final scoreSizes = calloc<IntPtr>(embCount);

    try {
      for (int i = 0; i < embCount; i++) {
        final embPtr = calloc<Float>(dim);
        for (int j = 0; j < dim && j < embeddings[i].length; j++) {
          embPtr[j] = embeddings[i][j];
        }
        embPtrs[i] = embPtr;
      }

      final result = bindings.cactusIndexQuery(
        Pointer.fromAddress(_handle!),
        embPtrs,
        embCount,
        dim,
        optionsJsonC,
        idBuffers,
        idSizes,
        scoreBuffers,
        scoreSizes,
      );

      if (result <= 0) {
        return CactusIndexQueryResult();
      }

      final resultIds = <List<int>>[];
      final resultScores = <List<double>>[];

      for (int i = 0; i < embCount; i++) {
        final count = idSizes[i];
        final ids = <int>[];
        final scores = <double>[];

        if (idBuffers[i] != nullptr && count > 0) {
          for (int j = 0; j < count; j++) {
            ids.add(idBuffers[i][j]);
          }
        }

        if (scoreBuffers[i] != nullptr && count > 0) {
          for (int j = 0; j < count; j++) {
            scores.add(scoreBuffers[i][j]);
          }
        }

        resultIds.add(ids);
        resultScores.add(scores);
      }

      return CactusIndexQueryResult(ids: resultIds, scores: resultScores);
    } finally {
      for (int i = 0; i < embCount; i++) {
        if (embPtrs[i] != nullptr) calloc.free(embPtrs[i]);
      }
      calloc.free(embPtrs);
      calloc.free(optionsJsonC);
      calloc.free(idBuffers);
      calloc.free(idSizes);
      calloc.free(scoreBuffers);
      calloc.free(scoreSizes);
    }
  }

  Future<void> compact() async {
    await _ensureInitialized();
    final result = bindings.cactusIndexCompact(Pointer.fromAddress(_handle!));
    if (result <= 0) {
      throw CactusException('Failed to compact index');
    }
  }

  Future<void> destroy() async {
    if (!_isInitialized) return;
    bindings.cactusIndexDestroy(Pointer.fromAddress(_handle!));
    _handle = null;
    _isInitialized = false;
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) await init();
  }
}
