import 'package:cactus/cactus.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(minutes: 3));
const _sttModel = 'whisper-tiny';
const _sttQuant = 'int4';

void main() {
  group('CactusSTT unit', () {
    test('getModelName returns correct format', () {
      final stt = CactusSTT(model: _sttModel, options: const CactusModelOptions(quantization: _sttQuant));
      expect(stt.getModelName(), equals('$_sttModel-$_sttQuant'));
    });

    test('default model is whisper-small', () {
      expect(CactusSTT().model, equals('whisper-small'));
    });

    test('destroy is idempotent', () async {
      final stt = CactusSTT(model: _sttModel, options: const CactusModelOptions(quantization: _sttQuant));
      await stt.destroy();
      await stt.destroy();
    });
  });

  group('CactusSTT integration', () {
    late CactusSTT stt;

    setUpAll(() async {
      stt = CactusSTT(model: _sttModel, options: const CactusModelOptions(quantization: _sttQuant));
      await stt.download();
      await stt.init();
    });

    tearDownAll(() async {
      await stt.destroy();
    });

    test('init is idempotent', () async {
      await stt.init();
    });

    test('transcribe with PCM data', () async {
      final result = await stt.transcribe(
        audio: List<int>.filled(16000, 0),
        prompt: CactusSTT.defaultPrompt,
      );
      expect(result, isNotNull);
    }, timeout: _timeout);

    test('transcribe rejects invalid audio type', () {
      expect(
        () => stt.transcribe(audio: 123, prompt: CactusSTT.defaultPrompt),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('streamTranscribe start/process/stop lifecycle', () async {
      await stt.streamTranscribeStart();
      final processResult = await stt.streamTranscribeProcess(audio: List<int>.filled(16000, 0));
      expect(processResult, isNotNull);
      final stopResult = await stt.streamTranscribeStop();
      expect(stopResult, isNotNull);
    }, timeout: _timeout);

    test('reset clears context', () async {
      await stt.reset();
    });

    test('getModels returns STT models', () async {
      final models = await stt.getModels();
      expect(models, isNotEmpty);
      for (final m in models) {
        expect(m.capabilities, contains('transcription'));
      }
    }, timeout: _timeout);
  });
}
