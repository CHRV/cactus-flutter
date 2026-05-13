import 'dart:io';

import 'package:cactus/models/types.dart';
import 'package:cactus/context.dart' as context;
import 'package:path_provider/path_provider.dart';

/// A vector index service that manages embeddings, documents, and metadata
/// for similarity search.
class CactusIndex {
  context.CactusIndex? _wrapper;
  bool _isInitialized = false;

  /// The name of this index, used to locate its directory on disk.
  final String name;

  /// The dimensionality of embeddings stored in this index.
  final int embeddingDim;

  /// Creates a [CactusIndex] instance.
  ///
  /// [name]: unique identifier for the index.
  /// [embeddingDim]: the dimension of vectors to be stored.
  CactusIndex({
    required this.name,
    required this.embeddingDim,
  });

  /// Initializes the underlying native index at `{docDir}/indices/[name]`.
  ///
  /// Creates the directory if it does not exist. Safe to call multiple times.
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

  /// Adds embeddings, documents, and optional metadata to the index.
  ///
  /// [ids]: unique integer identifiers for each entry.
  /// [documents]: text strings associated with each embedding.
  /// [embeddings]: vector representations to index.
  /// [metadatas]: optional metadata strings for each entry.
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

  /// Deletes entries from the index by their [ids].
  Future<void> delete({required List<int> ids}) async {
    await _ensureInitialized();
    _wrapper!.delete(ids: ids);
  }

  /// Retrieves entries by their [ids].
  ///
  /// Returns a [CactusIndexGetResult] containing the matching documents,
  /// embeddings, and metadata.
  Future<CactusIndexGetResult> get({required List<int> ids}) async {
    await _ensureInitialized();
    return _wrapper!.get(ids: ids);
  }

  /// Queries the index for the nearest neighbors of the given [embeddings].
  ///
  /// [embeddings]: query vectors to search against.
  /// [options]: optional query parameters (e.g. top-k).
  /// Returns a [CactusIndexQueryResult] with ranked results.
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

  /// Compacts the index to reclaim space from deleted entries.
  Future<void> compact() async {
    await _ensureInitialized();
    _wrapper!.compact();
  }

  /// Destroys the native index wrapper and resets initialization state.
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
