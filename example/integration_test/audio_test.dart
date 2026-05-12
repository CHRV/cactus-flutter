import 'package:cactus/cactus.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(minutes: 5));

void main() {
  group('CactusAudio unit', () {
    test('getModelName returns correct format', () {
      final audio = CactusAudio(options: const CactusModelOptions(quantization: 'int4'));
      expect(audio.getModelName(), equals('silero-vad-int4'));
    });

    test('default model is silero-vad', () {
      expect(CactusAudio().model, equals('silero-vad'));
    });

    test('destroy is idempotent', () async {
      final audio = CactusAudio(options: const CactusModelOptions(quantization: 'int4'));
      await audio.destroy();
      await audio.destroy();
    });
  });

  group('CactusAudio integration', () {
    late CactusAudio audio;

    setUpAll(() async {
      audio = CactusAudio(options: const CactusModelOptions(quantization: 'int4'));
    });

    tearDownAll(() async {
      await audio.destroy();
    });

    test('download and init', () async {
      await audio.download();
      await audio.init();
    }, timeout: Timeout(Duration(minutes: 10)));

    test('init is idempotent', () async {
      await audio.init();
    });

    test('vad with PCM data', () async {
      final result = await audio.vad(audio: List<int>.filled(16000, 0));
      expect(result, isNotNull);
      expect(result.segments, isNotNull);
    }, timeout: _timeout);

    test('vad rejects invalid audio type', () {
      expect(
        () => audio.vad(audio: 123),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getModels returns audio models', () async {
      final models = await audio.getModels();
      expect(models, isNotEmpty);
      for (final m in models) {
        expect(
          m.capabilities,
          anyOf(contains('vad'), contains('diarization'), contains('speaker-embed')),
        );
      }
    }, timeout: _timeout);
  });
}
