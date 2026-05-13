import 'package:cactus/services/bindings.dart' as bindings;

class CactusConfig {
  static const String _defaultHuggingFaceOrg = 'Cactus-Compute';
  static String? _customHuggingFaceOrg;
  static String get huggingFaceOrg => _customHuggingFaceOrg?.isNotEmpty == true
      ? _customHuggingFaceOrg!
      : _defaultHuggingFaceOrg;

  static setHuggingFaceOrg(String org) {
    _customHuggingFaceOrg = org.isEmpty ? null : org;
  }

  static void setTelemetryEnvironment(String cacheLocation) {
    bindings.cactusSetTelemetryEnvironment(cacheLocation);
  }

  static void setAppId(String appId) {
    bindings.cactusSetAppId(appId);
  }

  static void telemetryFlush() {
    bindings.cactusTelemetryFlush();
  }

  static void telemetryShutdown() {
    bindings.cactusTelemetryShutdown();
  }

  static void logSetLevel(int level) {
    bindings.cactusLogSetLevel(level);
  }
}
