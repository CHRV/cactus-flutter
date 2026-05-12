import 'dart:io';
import 'dart:typed_data';

import 'package:cactus/cactus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

const _timeout = Timeout(Duration(minutes: 3));
const _sttModel = 'whisper-tiny';
const _sttQuant = 'int4';

/// Loads a WAV file from assets and returns raw PCM samples as int16 List.
Future<List<int>> _loadPcmFromAsset() async {
  final data = await rootBundle.load('assets/test_audio.wav');
  final bytes = data.buffer.asUint8List();
  // Standard WAV header is 44 bytes for mono 16-bit PCM
  // Data starts at byte 44
  final pcmBytes = bytes.sublist(44);
  // Convert little-endian int16 bytes to List<int>
  final samples = <int>[];
  final buffer = ByteData.view(pcmBytes.buffer);
  for (var i = 0; i < pcmBytes.lengthInBytes; i += 2) {
    samples.add(buffer.getInt16(i, Endian.little));
  }
  return samples;
}

/// Copies a test audio asset to a temp file and returns the file path.
Future<String> _copyAudioToTemp() async {
  final data = await rootBundle.load('assets/test_audio.wav');
  final dir = await getApplicationDocumentsDirectory();
  final tempDir = Directory('${dir.path}/stt_test_audio');
  if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
  final file = File('${tempDir.path}/test_audio.wav');
  await file.writeAsBytes(data.buffer.asUint8List());
  return file.path;
}

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
    late List<int> pcmData;
    late String audioFilePath;

    setUpAll(() async {
      stt = CactusSTT(model: _sttModel, options: const CactusModelOptions(quantization: _sttQuant));
      await stt.download();
      await stt.init();
      pcmData = await _loadPcmFromAsset();
      audioFilePath = await _copyAudioToTemp();
    });

    tearDownAll(() async {
      await stt.destroy();
      final dir = await getApplicationDocumentsDirectory();
      final tempDir = Directory('${dir.path}/stt_test_audio');
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('init is idempotent', () async {
      await stt.init();
    });

    test('transcribe with PCM data', () async {
      final result = await stt.transcribe(
        audio: pcmData,
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

    test('detectLanguage detects language from audio file', () async {
      final result = await stt.detectLanguage(audio: audioFilePath);
      expect(result, isNotNull);
    }, timeout: _timeout);

    test('audioEmbed returns embedding from audio file', () async {
      final result = await stt.audioEmbed(audioPath: audioFilePath);
      expect(result, isNotNull);
      expect(result.embedding, isNotEmpty);
    }, timeout: _timeout);

    test('stop halts processing', () async {
      await stt.stop();
      // Verify we can still use the model after stop
      final result = await stt.transcribe(
        audio: List<int>.filled(16000, 0),
        prompt: CactusSTT.defaultPrompt,
      );
      expect(result, isNotNull);
    }, timeout: _timeout);

    test('getModels returns STT models', () async {
      final models = await stt.getModels();
      expect(models, isNotEmpty);
      for (final m in models) {
        expect(m.capabilities, contains('transcription'));
      }
    }, timeout: _timeout);
  });
}