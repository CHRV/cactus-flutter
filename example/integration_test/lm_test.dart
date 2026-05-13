@Timeout(Duration(hours: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cactus/cactus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

const _timeout = Timeout(Duration(hours: 2));
const _lmModel = 'lfm2-vl-450m';
const _lmQuant = 'int4';

void main() {
  group('CactusLM unit', () {
    test('getModelName returns correct format', () {
      final lm = CactusLM(
          model: _lmModel,
          options: const CactusModelOptions(quantization: _lmQuant));
      expect(lm.getModelName(), equals('$_lmModel-$_lmQuant'));
    });

    test('getModelName with pro includes -pro suffix', () {
      final lm = CactusLM(
          model: 'qwen3-0.6b',
          options: const CactusModelOptions(quantization: 'int8', pro: true));
      expect(lm.getModelName(), equals('qwen3-0.6b-int8-pro'));
    });

    test('default model is qwen3-0.6b', () {
      expect(CactusLM().model, equals('qwen3-0.6b'));
    });

    test('quantization exceptions are applied', () {
      expect(CactusLM(model: 'gemma-3-270m-it').options.quantization,
          equals('int8'));
    });

    test('destroy is idempotent', () async {
      final lm = CactusLM(
          model: _lmModel,
          options: const CactusModelOptions(quantization: _lmQuant));
      lm.destroy();
      lm.destroy();
    });
  });

  group('CactusLM integration', () {
    late CactusLM lm;

    setUpAll(() async {
      lm = CactusLM(
          model: _lmModel,
          options: const CactusModelOptions(quantization: _lmQuant));
    });

    tearDownAll(() async {
      lm.destroy();
    });

    test('prepare model', () async {
      await lm.download();
      await lm.init();
    }, timeout: _timeout);

    test('init is idempotent', () async {
      await lm.init();
    });

    test('complete returns a result', () async {
      final result = await lm.complete(
        messages: [
          CactusLMMessage(role: CactusLMRole.user, content: 'Say hi.')
        ],
        options: const CactusLMCompleteOptions(maxTokens: 16),
      );
      expect(result.success, isTrue);
      expect(result.response, isNotEmpty);
    }, timeout: _timeout);

    test('complete with onToken callback', () async {
      final tokens = <String>[];
      final result = await lm.complete(
        messages: [
          CactusLMMessage(role: CactusLMRole.user, content: 'Say hi.')
        ],
        options: const CactusLMCompleteOptions(maxTokens: 16),
        onToken: (token) {
          tokens.add(token);
        },
      );
      expect(result.success, isTrue);
      expect(tokens, isNotEmpty);
    }, timeout: _timeout);

    test('embed returns embedding vector', () async {
      final result = await lm.embed(text: 'Hello');
      expect(result.embedding, isNotEmpty);
    }, timeout: _timeout);

    test('tokenize returns token IDs', () async {
      final result = await lm.tokenize(text: 'Hello world');
      expect(result.tokens, isNotEmpty);
      expect(result.tokens.every((t) => t >= 0), isTrue);
    }, timeout: _timeout);

    test('scoreWindow returns logprob', () async {
      const text = 'The quick brown fox';
      final tokenized = await lm.tokenize(text: text);
      expect(tokenized.tokens, isNotEmpty);

      final tokens = tokenized.tokens;
      final result = await lm.scoreWindow(
        tokens: tokens,
        start: 0,
        end: tokens.length - 1,
        context: tokens.length,
      );
      expect(result.score, isNotNull);
    }, timeout: _timeout);

    test('imageEmbed returns embedding vector', () async {
      final dir = await getTemporaryDirectory();
      final imagePath = '${dir.path}/test_image.png';
      const base64Png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
      await File(imagePath).writeAsBytes(base64.decode(base64Png));

      final result = await lm.imageEmbed(imagePath: imagePath);
      expect(result.embedding, isNotEmpty);

      await File(imagePath).delete();
    }, timeout: _timeout);

    test('prefill returns result', () async {
      final result = await lm
          .prefill(messages: [
            CactusLMMessage(role: CactusLMRole.user, content: 'Hi')
          ]);
      expect(result.success, isTrue);
    }, timeout: _timeout);

    test('reset clears context', () async {
      await lm.complete(
        messages: [
          CactusLMMessage(role: CactusLMRole.user, content: 'Remember: 42')
        ],
        options: const CactusLMCompleteOptions(maxTokens: 16),
      );
      await lm.reset();
      final result = await lm.complete(
        messages: [
          CactusLMMessage(role: CactusLMRole.user, content: 'What?')
        ],
        options: const CactusLMCompleteOptions(maxTokens: 16),
      );
      expect(result.success, isTrue);
    }, timeout: _timeout);

    test('stop halts generation', () async {
      final completer = Completer<void>();
      var tokenCount = 0;

      unawaited(lm.complete(
        messages: [
          CactusLMMessage(
              role: CactusLMRole.user,
              content:
                  'Write a very long story with many chapters and characters')
        ],
        options: const CactusLMCompleteOptions(maxTokens: 512),
        onToken: (_) {
          tokenCount++;
          if (tokenCount >= 3 && !completer.isCompleted) {
            lm.stop();
            completer.complete();
          }
        },
      ));

      await completer.future.timeout(Duration(minutes: 5));
      expect(tokenCount, greaterThanOrEqualTo(3));
    }, timeout: _timeout);

    test('getModels returns non-empty list', () async {
      final models = await CactusLM().getModels();
      expect(models, isNotEmpty);
    }, timeout: _timeout);
  });

  group('CactusLM RAG integration', () {
    late CactusLM lmWithCorpus;

    setUpAll(() async {
      final dir = await getApplicationDocumentsDirectory();
      final corpusDir = '${dir.path}/corpus/test-rag';
      await Directory(corpusDir).create(recursive: true);

      await File('$corpusDir/doc1.txt')
          .writeAsString('The quick brown fox jumps over the lazy dog.');
      await File('$corpusDir/doc2.txt').writeAsString(
          'Machine learning enables computers to learn from data.');
      await File('$corpusDir/doc3.txt')
          .writeAsString('The capital of France is Paris.');

      lmWithCorpus = CactusLM(
        model: _lmModel,
        corpusDir: corpusDir,
        options: const CactusModelOptions(quantization: _lmQuant),
      );
    });

    tearDownAll(() async {
      lmWithCorpus.destroy();
      final dir = await getApplicationDocumentsDirectory();
      final corpusDir = '${dir.path}/corpus/test-rag';
      Directory(corpusDir).delete(recursive: true);
    });

    test('prepare rag model', () async {
      await lmWithCorpus.download();
      await lmWithCorpus.init();
    }, timeout: _timeout);

    test('ragQuery returns relevant chunks', () async {
      final result = await lmWithCorpus.ragQuery(
          query: 'What animal is quick and brown?', topK: 3);
      expect(result.chunks, isNotEmpty);
      final hasRelevantChunk = result.chunks.any((c) =>
          c.content.toLowerCase().contains('fox') ||
          c.content.toLowerCase().contains('quick') ||
          c.content.toLowerCase().contains('brown'));
      expect(hasRelevantChunk, isTrue);
    }, timeout: _timeout);

    test('ragQuery returns limited chunks for unrelated query', () async {
      final result = await lmWithCorpus.ragQuery(
          query: 'completely unrelated topic about quantum physics', topK: 1);
      expect(result.chunks.length, lessThanOrEqualTo(1));
    }, timeout: _timeout);
  });
}
