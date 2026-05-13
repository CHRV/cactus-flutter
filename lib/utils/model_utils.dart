import 'package:cactus/models/types.dart';
import 'package:path_provider/path_provider.dart';

/// Returns `true` if [m] is an absolute filesystem path or a `file://` URI.
///
/// [m]: The string to check.
/// Returns: Whether the string looks like a local path.
bool isModelPath(String m) => m.startsWith('/') || m.startsWith('file://');

/// Builds a model identifier string that includes quantization and Pro flag.
///
/// [model]: The base model name.
/// [options]: The model options containing quantization and Pro settings.
/// Returns: The formatted model name.
String modelName(String model, CactusModelOptions options) =>
    '$model-${options.quantization}${options.pro ? '-pro' : ''}';

/// Resolves a model identifier to an absolute filesystem path.
///
/// If [model] is already a local path (absolute or `file://`), the
/// `file://` prefix is stripped and the path is returned as-is.
/// Otherwise the model is assumed to be a name stored under the
/// application documents `models/` directory.
///
/// [model]: The model path or name to resolve.
/// Returns: The absolute filesystem path to the model.
Future<String> resolveModelPath(String model) async {
  if (isModelPath(model)) return model.replaceFirst('file://', '');
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/models/$model';
}
