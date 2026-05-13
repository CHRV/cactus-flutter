import 'package:cactus/services/bindings.dart' as bindings;

/// Global configuration for the Cactus SDK including telemetry, logging,
/// and the Hugging Face org used for model downloads.
class CactusConfig {
  static const String _defaultHuggingFaceOrg = 'Cactus-Compute';
  static String? _customHuggingFaceOrg;

  /// The Hugging Face organization used to resolve model sources.
  ///
  /// Defaults to `'Cactus-Compute'` unless overridden via
  /// [setHuggingFaceOrg].
  static String get huggingFaceOrg => _customHuggingFaceOrg?.isNotEmpty == true
      ? _customHuggingFaceOrg!
      : _defaultHuggingFaceOrg;

  /// Overrides the default Hugging Face organization for model lookups.
  ///
  /// [org]: the organization name. An empty string resets to the default.
  static setHuggingFaceOrg(String org) {
    _customHuggingFaceOrg = org.isEmpty ? null : org;
  }

  /// Sets the telemetry cache directory on the native side.
  ///
  /// [cacheLocation]: absolute path to the cache directory.
  static void setTelemetryEnvironment(String cacheLocation) {
    bindings.cactusSetTelemetryEnvironment(cacheLocation);
  }

  /// Sets the application identifier reported with telemetry.
  ///
  /// [appId]: a string identifying the consuming application.
  static void setAppId(String appId) {
    bindings.cactusSetAppId(appId);
  }

  /// Flushes any pending telemetry events to the backend.
  static void telemetryFlush() {
    bindings.cactusTelemetryFlush();
  }

  /// Shuts down the telemetry subsystem, flushing remaining events.
  static void telemetryShutdown() {
    bindings.cactusTelemetryShutdown();
  }

  /// Sets the native log verbosity level.
  ///
  /// [level]: an integer log level (e.g. 0 = debug, 1 = info, 2 = warn,
  /// 3 = error).
  static void logSetLevel(int level) {
    bindings.cactusLogSetLevel(level);
  }
}
