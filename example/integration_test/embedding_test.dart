import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Embedding Pipeline', () {
    late TestHelper helper;

    setUp(() {
      helper = TestHelper();
    });

    tearDown(() async {
      await helper.teardownModel();
    });

    testWidgets('generateEmbedding returns valid embedding vector', (tester) async {
      final lm = await helper.setupModel(
        model: 'lfm2-vl-450m',
        quantization: 'int4',
        skipDownload: true,
      );

      final result = await lm.generateEmbedding(text: 'Hello world');

      expect(result.success, isTrue);
      expect(result.dimension, greaterThan(0));
      expect(result.embeddings.length, equals(result.dimension));
      expect(result.embeddings.any((v) => v != 0.0), isTrue);
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
