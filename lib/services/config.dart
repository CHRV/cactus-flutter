import 'dart:io';

import 'package:cactus/src/services/api/telemetry.dart';
import 'package:cactus/src/services/bindings.dart' as bindings;
import 'package:ffi/ffi.dart';

class CactusConfig {

  static String? telemetryToken;
  static bool isTelemetryEnabled = true;
  static String? cactusProKey;

  static setTelemetryToken(String token) {
    telemetryToken = token.isEmpty ? null : token;
  }

  static setProKey(String token) {
    cactusProKey = token.isEmpty ? null : token;
  }

  static bool get isInitialized => Telemetry.isInitialized;

  static void setTelemetryEnvironment(String cacheLocation) {
    if (!Platform.isAndroid) return;
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
