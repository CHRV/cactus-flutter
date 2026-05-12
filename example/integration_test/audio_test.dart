import 'dart:typed_data';

import 'package:cactus/cactus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(minutes: 5));

/// Loads a WAV file from assets and returns raw PCM samples as Float32List.
Future<Float32List> _loadPcmFromAsset() async {
  final data = await rootBundle.load('assets/test_audio.wav');
  final bytes = data.buffer.asUint8List();
  // Standard WAV header is 44 bytes for mono 16-bit PCM
  final pcmBytes = bytes.sublist(44);
  // Convert little-endian int16 bytes to Float32List in [-1.0, 1.0]
  final buffer = ByteData.view(pcmBytes.buffer);
  final sampleCount = pcmBytes.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    final int16 = buffer.getInt16(i * 2, Endian.little);
    samples[i] = int16 / 32768.0;
  }
  return samples;
}

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
    late Float32List pcmData;

    setUpAll(() async {
      audio = CactusAudio(options: const CactusModelOptions(quantization: 'int4'));
      pcmData = await _loadPcmFromAsset();
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
      final result = await audio.vad(audio: pcmData.buffer.asUint8List());
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

    test('diarize returns speaker segments from audio file', () async {
      final result = await audio.diarize(
        audio: pcmData.buffer.asUint8List(),
        options: const CactusAudioDiarizeOptions(numSpeakers: 2),
      );
      expect(result, isNotNull);
      expect(result.numSpeakers, greaterThanOrEqualTo(0));
    }, timeout: _timeout);

    test('embedSpeaker returns embedding from audio file', () async {
      final result = await audio.embedSpeaker(
        audio: pcmData.buffer.asUint8List(),
      );
      expect(result, isNotNull);
      expect(result.embedding, isNotEmpty);
    }, timeout: _timeout);
  });
}