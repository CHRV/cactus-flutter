import 'package:cactus/src/services/bindings.dart' as bindings;
import 'package:ffi/ffi.dart';

class CactusConfig {

  static const String _defaultHuggingFaceOrg = 'Cactus-Compute';
  static String? _customHuggingFaceOrg;
  static String get huggingFaceOrg => _customHuggingFaceOrg?.isNotEmpty == true ? _customHuggingFaceOrg! : _defaultHuggingFaceOrg;

  static setHuggingFaceOrg(String org) {
    _customHuggingFaceOrg = org.isEmpty ? null : org;
  }

  static void setTelemetryEnvironment(String cacheLocation) {
    final frameworkC = 'flutter'.toNativeUtf8(allocator: calloc);
    final cacheLocationC = cacheLocation.toNativeUtf8(allocator: calloc);
    final versionC = '1.14.0'.toNativeUtf8(allocator: calloc);
    try {
      bindings.cactusSetTelemetryEnvironment(frameworkC, cacheLocationC, versionC);
    } finally {
      calloc.free(frameworkC);
      calloc.free(cacheLocationC);
      calloc.free(versionC);
    }
  }

  static void setAppId(String appId) {
    final appIdC = appId.toNativeUtf8(allocator: calloc);
    try {
      bindings.cactusSetAppId(appIdC);
    } finally {
      calloc.free(appIdC);
    }
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
