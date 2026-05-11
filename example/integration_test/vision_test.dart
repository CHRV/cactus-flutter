import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cactus/cactus.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Vision Pipeline', () {
    late TestHelper helper;

    setUp(() {
      helper = TestHelper();
    });

    tearDown(() async {
      await helper.teardownModel();
    });

    testWidgets('generateCompletion with image returns valid result', (tester) async {
      final lm = await helper.setupModel(
        model: 'lfm2-vl-450m',
        quantization: 'int4',
        skipDownload: true,
      );

      final byteData = await rootBundle.load('assets/test_image.png');
      final appDir = await getApplicationDocumentsDirectory();
      final imagePath = '${appDir.path}/test_image.png';
      await File(imagePath).writeAsBytes(byteData.buffer.asUint8List());

      final result = await lm.generateCompletion(
        messages: [
          ChatMessage(
            role: 'user',
            content: 'Describe this image briefly.',
            images: [imagePath],
          ),
        ],
        params: CactusCompletionParams(maxTokens: 64),
      );

      expect(result.success, isTrue);
      expect(result.response, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('generateEmbedding on vision model returns valid result', (tester) async {
      final lm = await helper.setupModel(
        model: 'lfm2-vl-450m',
        quantization: 'int4',
        skipDownload: true,
      );

      final result = await lm.generateEmbedding(text: 'A green image');

      expect(result.success, isTrue);
      expect(result.embeddings, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
