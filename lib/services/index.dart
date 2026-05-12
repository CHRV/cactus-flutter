import 'dart:io';

import 'package:cactus/models/types.dart';
import 'package:cactus/src/services/context.dart' as context;
import 'package:path_provider/path_provider.dart';

class CactusIndex {
  context.CactusIndex? _wrapper;
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

    await Directory(indexDir).create(recursive: true);

    _wrapper = await context.CactusIndex.init(
      indexPath: indexDir,
      embeddingDim: embeddingDim,
    );
    _isInitialized = true;
  }

  Future<void> add({
    required List<int> ids,
    required List<String> documents,
    required List<List<double>> embeddings,
    List<String>? metadatas,
  }) async {
    await _ensureInitialized();
    _wrapper!.add(
      ids: ids,
      documents: documents,
      embeddings: embeddings,
      metadatas: metadatas,
      embeddingDim: embeddingDim,
    );
  }

  Future<void> delete({required List<int> ids}) async {
    await _ensureInitialized();
    _wrapper!.delete(ids: ids);
  }

  Future<CactusIndexGetResult> get({required List<int> ids}) async {
    await _ensureInitialized();
    return _wrapper!.get(ids: ids);
  }

  Future<CactusIndexQueryResult> query({
    required List<List<double>> embeddings,
    CactusIndexQueryOptions? options,
  }) async {
    await _ensureInitialized();
    return _wrapper!.query(
      embeddings: embeddings,
      embeddingDim: embeddingDim,
      options: options,
    );
  }

  Future<void> compact() async {
    await _ensureInitialized();
    _wrapper!.compact();
  }

  Future<void> destroy() async {
    if (!_isInitialized) return;
    _wrapper?.destroy();
    _wrapper = null;
    _isInitialized = false;
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) await init();
  }
}
