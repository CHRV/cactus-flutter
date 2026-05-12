import 'dart:typed_data';

import 'package:cactus/cactus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(minutes: 5));
const _spkModel = 'wespeaker-voxceleb-resnet34-LM';

Future<Float32List> _loadPcmFromAsset() async {
  final data = await rootBundle.load('assets/test_audio.wav');
  final bytes = data.buffer.asUint8List();
  final pcmBytes = bytes.sublist(44);
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
  group('CactusAudio speaker embedding integration ($_spkModel)', () {
    late CactusAudio audio;
    late Float32List pcmData;

    setUpAll(() async {
      audio = CactusAudio(
        model: _spkModel,
        options: const CactusModelOptions(quantization: 'int8'),
      );
      pcmData = await _loadPcmFromAsset();
    });

    tearDownAll(() async {
      await audio.destroy();
    });

    test('download and init', () async {
      await audio.download();
      await audio.init();
    }, timeout: Timeout(Duration(minutes: 10)));

    test('embedSpeaker returns embedding from PCM data', () async {
      final result = await audio.embedSpeaker(
        audio: pcmData.buffer.asUint8List(),
      );
      expect(result, isNotNull);
      expect(result.embedding, isNotEmpty);
    }, timeout: _timeout);
  });
}