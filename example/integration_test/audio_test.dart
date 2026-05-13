import 'dart:io';

import 'package:cactus/cactus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

const _timeout = Timeout(Duration(minutes: 5));
const _vadModel = 'silero-vad';
const _diarizeModel = 'segmentation-3.0';
const _audioQuant = 'int4';

Future<String> _copyAudioToTemp() async {
  final data = await rootBundle.load('assets/test_audio.wav');
  final dir = await getApplicationDocumentsDirectory();
  final tempDir = Directory('${dir.path}/audio_test_audio');
  if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
  final file = File('${tempDir.path}/test_audio.wav');
  await file.writeAsBytes(data.buffer.asUint8List());
  return file.path;
}

void main() {
  group('CactusAudio unit', () {
    test('getModelName returns correct format for silero-vad', () {
      final audio = CactusAudio(model: _vadModel, options: const CactusModelOptions(quantization: _audioQuant));
      expect(audio.getModelName(), equals('$_vadModel-$_audioQuant'));
    });

    test('getModelName returns correct format for segmentation-3.0', () {
      final audio = CactusAudio(model: _diarizeModel, options: const CactusModelOptions(quantization: _audioQuant));
      expect(audio.getModelName(), equals('$_diarizeModel-$_audioQuant'));
    });

    test('default model is silero-vad', () {
      expect(CactusAudio().model, equals('silero-vad'));
    });

    test('destroy is idempotent', () async {
      final audio = CactusAudio(model: _vadModel, options: const CactusModelOptions(quantization: _audioQuant));
      await audio.destroy();
      await audio.destroy();
    });

    test('vad rejects invalid audio type', () {
      final audio = CactusAudio(model: _vadModel, options: const CactusModelOptions(quantization: _audioQuant));
      expect(
        () => audio.vad(audio: 123),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CactusAudio VAD integration ($_vadModel)', () {
    late CactusAudio audio;
    late String audioFilePath;

    setUpAll(() async {
      audio = CactusAudio(
        model: _vadModel,
        options: const CactusModelOptions(quantization: _audioQuant),
      );
      audioFilePath = await _copyAudioToTemp();
    });

    tearDownAll(() async {
      await audio.destroy();
      final dir = await getApplicationDocumentsDirectory();
      final tempDir = Directory('${dir.path}/audio_test_audio');
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('download and init', () async {
      await audio.download();
      await audio.init();
    }, timeout: Timeout(Duration(minutes: 10)));

    test('init is idempotent', () async {
      await audio.init();
    });

    test('vad with audio file path', () async {
      final result = await audio.vad(audio: audioFilePath);
      expect(result, isNotNull);
      expect(result.segments, isNotNull);
    }, timeout: _timeout);
  });

  group('CactusAudio diarize integration ($_diarizeModel)', () {
    late CactusAudio audio;
    late String audioFilePath;

    setUpAll(() async {
      audio = CactusAudio(
        model: _diarizeModel,
        options: const CactusModelOptions(quantization: _audioQuant),
      );
      audioFilePath = await _copyAudioToTemp();
    });

    tearDownAll(() async {
      await audio.destroy();
    });

    test('download and init', () async {
      await audio.download();
      await audio.init();
    }, timeout: Timeout(Duration(minutes: 10)));

    test('diarize returns speaker segments from audio file', () async {
      final result = await audio.diarize(
        audio: audioFilePath,
        options: const CactusAudioDiarizeOptions(numSpeakers: 2),
      );
      expect(result, isNotNull);
      expect(result.numSpeakers, greaterThanOrEqualTo(0));
    }, timeout: _timeout);
  });
}