import 'package:cactus/cactus.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(minutes: 3));
const _lmModel = 'lfm2-350m';
const _lmQuant = 'int4';

void main() {
  group('CactusLM unit', () {
    test('getModelName returns correct format', () {
      final lm = CactusLM(model: _lmModel, options: const CactusModelOptions(quantization: _lmQuant));
      expect(lm.getModelName(), equals('$_lmModel-$_lmQuant'));
    });

    test('getModelName with pro includes -pro suffix', () {
      final lm = CactusLM(model: 'qwen3-0.6b', options: const CactusModelOptions(quantization: 'int8', pro: true));
      expect(lm.getModelName(), equals('qwen3-0.6b-int8-pro'));
    });

    test('default model is qwen3-0.6b', () {
      expect(CactusLM().model, equals('qwen3-0.6b'));
    });

    test('quantization exceptions are applied', () {
      expect(CactusLM(model: 'gemma-3-270m-it').options.quantization, equals('int8'));
    });

    test('destroy is idempotent', () async {
      final lm = CactusLM(model: _lmModel, options: const CactusModelOptions(quantization: _lmQuant));
      await lm.destroy();
      await lm.destroy();
    });
  });

  group('CactusLM integration', () {
    late CactusLM lm;

    setUpAll(() async {
      lm = CactusLM(model: _lmModel, options: const CactusModelOptions(quantization: _lmQuant));
      await lm.download();
      await lm.init();
    });

    tearDownAll(() async {
      await lm.destroy();
    });

    test('init is idempotent', () async {
      await lm.init();
    });

    test('complete returns a result', () async {
      final result = await lm.complete(
        messages: [CactusLMMessage(role: 'user', content: 'Say hi.')],
        options: const CactusLMCompleteOptions(maxTokens: 16),
      );
      expect(result.success, isTrue);
      expect(result.response, isNotEmpty);
    }, timeout: _timeout);

    test('complete with onToken callback', () async {
      final tokens = <String>[];
      final result = await lm.complete(
        messages: [CactusLMMessage(role: 'user', content: 'Say hi.')],
        options: const CactusLMCompleteOptions(maxTokens: 16),
        onToken: (token) { tokens.add(token); return true; },
      );
      expect(result.success, isTrue);
      expect(tokens, isNotEmpty);
    }, timeout: _timeout);

    test('embed returns embedding vector', () async {
      final result = await lm.embed(text: 'Hello');
      expect(result.embedding, isNotEmpty);
    }, timeout: _timeout);

    test('tokenize returns token IDs', () async {
      final result = await lm.tokenize(text: 'Hello');
      expect(result.tokens, isNotEmpty);
    }, timeout: _timeout);

    test('prefill returns result', () async {
      final result = await lm.prefill(messages: [CactusLMMessage(role: 'user', content: 'Hi')]);
      expect(result.success, isTrue);
    }, timeout: _timeout);

    test('reset clears context', () async {
      await lm.complete(
        messages: [CactusLMMessage(role: 'user', content: 'Remember: 42')],
        options: const CactusLMCompleteOptions(maxTokens: 16),
      );
      await lm.reset();
      final result = await lm.complete(
        messages: [CactusLMMessage(role: 'user', content: 'What?')],
        options: const CactusLMCompleteOptions(maxTokens: 16),
      );
      expect(result.success, isTrue);
    }, timeout: _timeout);

    test('getModels returns non-empty list', () async {
      final models = await CactusLM().getModels();
      expect(models, isNotEmpty);
    }, timeout: _timeout);
  });
}
