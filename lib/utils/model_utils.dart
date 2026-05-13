import 'package:cactus/models/types.dart';
import 'package:path_provider/path_provider.dart';

bool isModelPath(String m) => m.startsWith('/') || m.startsWith('file://');

String modelName(String model, CactusModelOptions options) =>
    '$model-${options.quantization}${options.pro ? '-pro' : ''}';

Future<String> resolveModelPath(String model) async {
  if (isModelPath(model)) return model.replaceFirst('file://', '');
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/models/$model';
}