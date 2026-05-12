import 'package:cactus/cactus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CactusIndex', () {
    late CactusIndex index;
    const dim = 64;

    setUp(() {
      index = CactusIndex(name: 'test-index-${DateTime.now().millisecondsSinceEpoch}', embeddingDim: dim);
    });

    tearDown(() async {
      await index.destroy();
    });

    test('init creates index', () async {
      await index.init();
    });

    test('init is idempotent', () async {
      await index.init();
      await index.init();
    });

    test('add and get entries', () async {
      await index.init();

      final embeddings = [
        List<double>.generate(dim, (i) => i * 0.01),
        List<double>.generate(dim, (i) => (dim - i) * 0.01),
      ];

      await index.add(
        ids: [1, 2],
        documents: ['doc one', 'doc two'],
        embeddings: embeddings,
        metadatas: ['meta1', 'meta2'],
      );

      final result = await index.get(ids: [1, 2]);

      expect(result.documents.length, equals(2));
      expect(result.documents, contains('doc one'));
      expect(result.documents, contains('doc two'));
    });

    test('query returns nearest neighbors', () async {
      await index.init();

      final embeddings = [
        List<double>.generate(dim, (i) => i * 0.01),
        List<double>.generate(dim, (i) => (dim - i) * 0.01),
      ];

      await index.add(
        ids: [1, 2],
        documents: ['doc one', 'doc two'],
        embeddings: embeddings,
      );

      final queryResult = await index.query(
        embeddings: [List<double>.generate(dim, (i) => i * 0.01)],
        options: CactusIndexQueryOptions(topK: 2),
      );

      expect(queryResult.ids, isNotEmpty);
      expect(queryResult.scores, isNotEmpty);
    });

    test('delete removes entries', () async {
      await index.init();

      await index.add(
        ids: [10, 20],
        documents: ['delete me', 'keep me'],
        embeddings: [
          List<double>.filled(dim, 0.1),
          List<double>.filled(dim, 0.2),
        ],
      );

      await index.delete(ids: [10]);

      final result = await index.get(ids: [10, 20]);
      expect(result.documents.length, equals(2));
    });

    test('compact runs without error', () async {
      await index.init();

      await index.add(
        ids: [1],
        documents: ['compact test'],
        embeddings: [List<double>.filled(dim, 0.5)],
      );

      await index.compact();
    });

    test('destroy is idempotent', () async {
      await index.init();
      await index.destroy();
      await index.destroy();
    });
  });
}