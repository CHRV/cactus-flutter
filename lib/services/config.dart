import 'dart:io';

import 'package:cactus/src/services/api/telemetry.dart';
import 'package:cactus/src/services/bindings.dart' as bindings;
import 'package:ffi/ffi.dart';

class CactusConfig {

  static const String _defaultSupabaseUrl = 'https://vlqqczxwyaodtcdmdmlw.supabase.co';
  static const String _defaultSupabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZscXFjenh3eWFvZHRjZG1kbWx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE1MTg2MzIsImV4cCI6MjA2NzA5NDYzMn0.nBzqGuK9j6RZ6mOPWU2boAC_5H9XDs-fPpo5P3WZYbI';
  static const String _defaultHuggingFaceOrg = 'Cactus-Compute';

  static String? _customSupabaseUrl;
  static String? _customSupabaseKey;
  static String? _customHuggingFaceOrg;

  static String get supabaseUrl => _customSupabaseUrl?.isNotEmpty == true ? _customSupabaseUrl! : _defaultSupabaseUrl;
  static String get supabaseKey => _customSupabaseKey?.isNotEmpty == true ? _customSupabaseKey! : _defaultSupabaseKey;
  static String get huggingFaceOrg => _customHuggingFaceOrg?.isNotEmpty == true ? _customHuggingFaceOrg! : _defaultHuggingFaceOrg;

  static String? telemetryToken;
  static bool isTelemetryEnabled = true;
  static String? cactusProKey;

  static setTelemetryToken(String token) {
    telemetryToken = token.isEmpty ? null : token;
  }

  static setProKey(String token) {
    cactusProKey = token.isEmpty ? null : token;
  }

  static setSupabaseUrl(String url) {
    _customSupabaseUrl = url.isEmpty ? null : url;
  }

  static setSupabaseKey(String key) {
    _customSupabaseKey = key.isEmpty ? null : key;
  }

  static setHuggingFaceOrg(String org) {
    _customHuggingFaceOrg = org.isEmpty ? null : org;
  }

  static resetConfig() {
    _customSupabaseUrl = null;
    _customSupabaseKey = null;
    _customHuggingFaceOrg = null;
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
