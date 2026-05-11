import 'dart:io';

import 'package:cactus/cactus.dart';
import 'package:cactus/src/utils/models/download.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _defaultModel = 'lfm2-350m';
const _defaultQuantization = 'int4';
const _testTimeout = Timeout(Duration(seconds: 180));

Future<CactusLM> _setupLM({String model = _defaultModel}) async {
  final lm = CactusLM();
  final onDisk = await DownloadService.modelExists(model);
  if (!onDisk) {
    await lm.downloadModel(model: model, quantization: _defaultQuantization);
  }
  await lm.initializeModel(params: CactusInitParams(model: model));
  return lm;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Embedding Pipeline', () {
    late CactusLM lm;

    setUp(() async {
      lm = await _setupLM();
    });

    tearDown(() {
      lm.unload();
    });

    testWidgets('generateEmbedding returns valid embedding vector', (tester) async {
      final result = await lm.generateEmbedding(text: 'Hello, world!');

      expect(result.success, isTrue);
      expect(result.embeddings, isNotNull);
      expect(result.embeddings.isNotEmpty, isTrue);
      expect(result.dimension, greaterThan(0));
      expect(result.embeddings.length, equals(result.dimension));
    }, timeout: _testTimeout);

    testWidgets('embedding dimension is consistent across calls', (tester) async {
      final result1 = await lm.generateEmbedding(text: 'First text');
      final result2 = await lm.generateEmbedding(text: 'Second text');

      expect(result1.success, isTrue);
      expect(result2.success, isTrue);
      expect(result1.embeddings.length, equals(result2.embeddings.length));
    }, timeout: _testTimeout);

    testWidgets('different texts produce different embeddings', (tester) async {
      final result1 = await lm.generateEmbedding(text: 'The cat sat on the mat');
      final result2 = await lm.generateEmbedding(text: 'Quantum physics equations');

      expect(result1.success, isTrue);
      expect(result2.success, isTrue);

      double dotProduct = 0;
      for (int i = 0; i < result1.embeddings.length; i++) {
        dotProduct += result1.embeddings[i] * result2.embeddings[i];
      }
      final norm1 = result1.embeddings.fold<double>(0, (sum, v) => sum + v * v);
      final norm2 = result2.embeddings.fold<double>(0, (sum, v) => sum + v * v);
      final cosineSim = dotProduct / (Math.sqrt(norm1) * Math.sqrt(norm2));

      expect(cosineSim, lessThan(0.99));
    }, timeout: _testTimeout);

    testWidgets('embedding values are normalized (unit length)', (tester) async {
      final result = await lm.generateEmbedding(text: 'Normalization test');

      expect(result.success, isTrue);
      final norm = result.embeddings.fold<double>(0, (sum, v) => sum + v * v);
      expect(norm, closeTo(1.0, 0.01));
    }, timeout: _testTimeout);
  });

  group('Text Generation Pipeline', () {
    late CactusLM lm;

    setUp(() async {
      lm = await _setupLM();
    });

    tearDown(() {
      lm.unload();
    });

    testWidgets('generateCompletion returns non-empty response', (tester) async {
      final result = await lm.generateCompletion(
        messages: [
          ChatMessage(role: 'user', content: 'What is the capital of France? Answer in one word.'),
        ],
        params: CactusCompletionParams(maxTokens: 20),
      );

      expect(result.success, isTrue);
      expect(result.response, isNotEmpty);
      expect(result.totalTokens, greaterThan(0));
    }, timeout: _testTimeout);

    testWidgets('completion metrics are populated', (tester) async {
      final result = await lm.generateCompletion(
        messages: [
          ChatMessage(role: 'user', content: 'Say hello.'),
        ],
        params: CactusCompletionParams(maxTokens: 10),
      );

      expect(result.success, isTrue);
      expect(result.timeToFirstTokenMs, greaterThan(0));
      expect(result.totalTimeMs, greaterThan(0));
      expect(result.tokensPerSecond, greaterThan(0));
      expect(result.ramUsageMb, greaterThan(0));
    }, timeout: _testTimeout);

    testWidgets('streaming completion yields tokens', (tester) async {
      final streamedResult = await lm.generateCompletionStream(
        messages: [
          ChatMessage(role: 'user', content: 'Count from 1 to 5.'),
        ],
        params: CactusCompletionParams(maxTokens: 30),
      );

      final tokens = <String>[];
      await for (final token in streamedResult.stream) {
        tokens.add(token);
      }

      final result = await streamedResult.result;
      expect(result.success, isTrue);
      expect(tokens, isNotEmpty);
    }, timeout: _testTimeout);

    testWidgets('multi-turn conversation maintains context', (tester) async {
      final result1 = await lm.generateCompletion(
        messages: [
          ChatMessage(role: 'user', content: 'My name is Alice. Remember it.'),
        ],
        params: CactusCompletionParams(maxTokens: 30),
      );
      expect(result1.success, isTrue);

      lm.reset();

      final result2 = await lm.generateCompletion(
        messages: [
          ChatMessage(role: 'user', content: 'My name is Alice. Remember it.'),
          ChatMessage(role: 'assistant', content: result1.response),
          ChatMessage(role: 'user', content: 'What is my name?'),
        ],
        params: CactusCompletionParams(maxTokens: 20),
      );
      expect(result2.success, isTrue);
      expect(result2.response.toLowerCase(), contains('alice'));
    }, timeout: _testTimeout);

    testWidgets('stop sequences work correctly', (tester) async {
      final result = await lm.generateCompletion(
        messages: [
          ChatMessage(role: 'user', content: 'Say the word hello and then stop.'),
        ],
        params: CactusCompletionParams(
          maxTokens: 50,
          stopSequences: ['\n'],
        ),
      );

      expect(result.success, isTrue);
    }, timeout: _testTimeout);
  });

  group('Speech-to-Text Pipeline', () {
    late CactusSTT stt;

    setUp(() async {
      stt = CactusSTT();
      final onDisk = await DownloadService.modelExists('whisper-tiny');
      if (!onDisk) {
        await stt.downloadModel(model: 'whisper-tiny');
      }
      await stt.initializeModel(params: CactusInitParams(model: 'whisper-tiny'));
    });

    tearDown(() {
      stt.unload();
    });

    testWidgets('STT model initializes successfully', (tester) async {
      expect(stt.isLoaded(), isTrue);
    }, timeout: _testTimeout);

    testWidgets('STT transcribe from file returns result', (tester) async {
      final docsDir = await getApplicationDocumentsDirectory();
      final testAudioPath = '${docsDir.path}/test_audio.wav';

      if (!await File(testAudioPath).exists()) {
        debugPrint('Skipping STT file test: no test_audio.wav available');
        return;
      }

      final result = await stt.transcribe(audioFilePath: testAudioPath);
      expect(result.success, isTrue);
      expect(result.text, isNotEmpty);
    }, timeout: _testTimeout);

    testWidgets('STT unload and reinitialize works', (tester) async {
      stt.unload();
      expect(stt.isLoaded(), isFalse);

      await stt.initializeModel(params: CactusInitParams(model: 'whisper-tiny'));
      expect(stt.isLoaded(), isTrue);
    }, timeout: _testTimeout);
  });

  group('Model Lifecycle', () {
    testWidgets('initialize and unload cycle works', (tester) async {
      final lm = await _setupLM();
      expect(lm.isLoaded(), isTrue);

      lm.unload();
      expect(lm.isLoaded(), isFalse);

      await lm.initializeModel(params: CactusInitParams(model: _defaultModel));
      expect(lm.isLoaded(), isTrue);

      lm.unload();
    }, timeout: _testTimeout);

    testWidgets('reset clears context without unloading', (tester) async {
      final lm = await _setupLM();
      expect(lm.isLoaded(), isTrue);

      lm.reset();
      expect(lm.isLoaded(), isTrue);

      final result = await lm.generateCompletion(
        messages: [
          ChatMessage(role: 'user', content: 'Hello'),
        ],
        params: CactusCompletionParams(maxTokens: 10),
      );
      expect(result.success, isTrue);

      lm.unload();
    }, timeout: _testTimeout);
  });

  group('CactusConfig Telemetry', () {
    testWidgets('setTelemetryEnvironment works', (tester) async {
      final docsDir = await getApplicationDocumentsDirectory();
      CactusConfig.setTelemetryEnvironment(docsDir.path);
    }, timeout: _testTimeout);

    testWidgets('setAppId works', (tester) async {
      CactusConfig.setAppId('test-app-id');
    }, timeout: _testTimeout);

    testWidgets('logSetLevel works', (tester) async {
      CactusConfig.logSetLevel(3);
    }, timeout: _testTimeout);
  });
}

class Math {
  static double sqrt(double x) {
    if (x <= 0) return 0;
    double lo = 0, hi = x;
    if (x < 1) hi = 1;
    for (int i = 0; i < 60; i++) {
      final mid = (lo + hi) / 2;
      if (mid * mid > x) hi = mid; else lo = mid;
    }
    return (lo + hi) / 2;
  }
}
