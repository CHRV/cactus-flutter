import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cactus/cactus.dart';
import 'test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('RAG Pipeline', () {
    late TestHelper helper;

    setUp(() {
      helper = TestHelper();
    });

    tearDown(() async {
      await helper.teardownModel();
    });

    testWidgets('store and search document', (tester) async {
      final lm = await helper.setupModel(
        model: 'lfm2-vl-450m',
        quantization: 'int4',
        skipDownload: true,
      );

      final rag = CactusRAG();
      await rag.initialize();

      rag.setEmbeddingGenerator((text) async {
        final result = await lm.generateEmbedding(text: text);
        return result.embeddings;
      });

      rag.setChunking(chunkSize: 500, chunkOverlap: 50);

      await rag.storeDocument(
        fileName: 'test_doc.txt',
        filePath: '/tmp/test_doc.txt',
        content: 'Cactus is a framework for running language models on mobile devices. '
            'It supports text completion, embeddings, and retrieval-augmented generation. '
            'The framework uses GGUF model format with quantization support.',
      );

      final results = await rag.search(text: 'What is Cactus?');

      expect(results, isNotEmpty);
      expect(results.first.chunk.content, isNotEmpty);
      expect(results.first.distance, isNotNull);

      await rag.close();
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
