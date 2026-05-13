import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

/// Generates a deterministic, unique project identifier for the app.
class CactusId {
  static String? _cached;

  /// Returns a UUID v5 derived from the package name and an optional [seed].
  ///
  /// The result is cached after the first call so subsequent invocations
  /// are synchronous.
  ///
  /// [seed]: A namespace seed string (default: `'v1'`).
  /// Returns: A stable UUID string unique to this app installation and seed.
  static Future<String> getProjectId({String seed = 'v1'}) async {
    if (_cached != null) return _cached!;
    final info = await PackageInfo.fromPlatform();
    final bundle = info.packageName;
    final ns = Namespace.url.value;
    final name = 'https://cactus-flutter/$bundle/$seed';
    _cached = const Uuid().v5(ns, name);
    return _cached!;
  }
}
