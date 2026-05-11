import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cactus/cactus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Model Registry Pipeline', () {
    testWidgets('fetchModels returns non-empty list with valid entries', (tester) async {
      final models = await HuggingFace.fetchModels();

      expect(models, isNotEmpty);

      for (final model in models) {
        expect(model.slug, isNotEmpty);
        expect(model.capabilities, isNotEmpty);
        expect(model.quantization, isNotEmpty);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('getModel returns lfm2-vl-450m with expected capabilities', (tester) async {
      final model = await HuggingFace.getModel('lfm2-vl-450m');

      expect(model, isNotNull);
      expect(model!.capabilities, contains('vision'));
      expect(model.capabilities, contains('text-embed'));
      expect(model.capabilities, contains('image-embed'));
      expect(model.quantization, contains('int4'));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
