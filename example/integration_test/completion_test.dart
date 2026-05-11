import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cactus/cactus.dart';
import 'test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Completion Pipeline', () {
    late TestHelper helper;

    setUp(() {
      helper = TestHelper();
    });

    tearDown(() async {
      await helper.teardownModel();
    });

    testWidgets('generateCompletion returns valid result', (tester) async {
      final lm = await helper.setupModel(
        model: 'lfm2-vl-450m',
        quantization: 'int4',
      );

      final result = await lm.generateCompletion(
        messages: [
          ChatMessage(role: 'system', content: 'You are a helpful assistant.'),
          ChatMessage(role: 'user', content: 'Say hello in one word.'),
        ],
        params: CactusCompletionParams(maxTokens: 32),
      );

      expect(result.success, isTrue);
      expect(result.response, isNotEmpty);
      expect(result.tokensPerSecond, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('generateCompletionStream emits tokens', (tester) async {
      final lm = await helper.setupModel(
        model: 'lfm2-vl-450m',
        quantization: 'int4',
        skipDownload: true,
      );

      final streamedResult = await lm.generateCompletionStream(
        messages: [
          ChatMessage(role: 'system', content: 'You are a helpful assistant.'),
          ChatMessage(role: 'user', content: 'Say hello in one word.'),
        ],
        params: CactusCompletionParams(maxTokens: 32),
      );

      final tokens = <String>[];
      await for (final token in streamedResult.stream) {
        tokens.add(token);
      }

      expect(tokens, isNotEmpty);

      final finalResult = await streamedResult.result;
      expect(finalResult.success, isTrue);
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
