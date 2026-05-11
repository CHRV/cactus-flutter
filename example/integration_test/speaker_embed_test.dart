import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Speaker Embed Pipeline (whisper-tiny)', () {
    late TestHelper helper;

    setUp(() {
      helper = TestHelper(defaultModel: 'whisper-tiny');
    });

    tearDown(() async {
      await helper.teardownModel();
    });

    testWidgets('download whisper-tiny and embedSpeaker returns valid embedding', (tester) async {
      final lm = await helper.setupModel(
        model: 'whisper-tiny',
        quantization: 'int4',
      );

      final pcmData = List<int>.filled(32000, 0);

      final result = await lm.embedSpeaker(pcmData: pcmData);

      expect(result.embedding, isNotEmpty);
      expect(result.embedding.any((v) => v != 0.0), isTrue);
    }, timeout: const Timeout(Duration(seconds: 120)));
  });

  group('Speaker Embed Pipeline (wespeaker)', () {
    late TestHelper helper;

    setUp(() {
      helper = TestHelper(defaultModel: 'wespeaker-voxceleb-resnet34-lm');
    });

    tearDown(() async {
      await helper.teardownModel();
    });

    testWidgets('download wespeaker and embedSpeaker returns valid embedding', (tester) async {
      final lm = await helper.setupModel(
        model: 'wespeaker-voxceleb-resnet34-lm',
        quantization: 'int4',
      );

      final pcmData = List<int>.filled(32000, 0);

      final result = await lm.embedSpeaker(pcmData: pcmData);

      expect(result.embedding, isNotEmpty);
      expect(result.embedding.any((v) => v != 0.0), isTrue);
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
