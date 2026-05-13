import 'dart:convert';
import 'dart:io';

import 'package:cactus/models/types.dart';
import 'package:cactus/services/config.dart';
import 'package:cactus/version.dart';
import 'package:flutter/foundation.dart';

const _kKnownCapabilities = <String>{
  'completion',
  'tools',
  'embed',
  'vision',
  'transcription',
  'vad',
  'audio',
  'speech-embed',
  'image-embed',
  'text-embed',
  'speaker-embed',
  'thinking',
  'diarization',
  'apple-npu',
};

/// Service class for interacting with the Hugging Face API to discover and
/// download Cactus models.
class HuggingFace {
  static Future<Map<String, CactusModel>>? _registryCache;

  /// Returns the cached registry of known Cactus models, fetching it from
  /// Hugging Face on the first call.
  ///
  /// Returns: A map of model slugs to [CactusModel] instances.
  static Future<Map<String, CactusModel>> getRegistry() async {
    return _registryCache ??= _fetchRegistry();
  }

  /// Clears the internal cache and re-fetches the full model registry from
  /// Hugging Face.
  ///
  /// Returns: A fresh map of model slugs to [CactusModel] instances.
  static Future<Map<String, CactusModel>> refreshRegistry() async {
    _registryCache = null;
    return getRegistry();
  }

  /// Returns a flat list of all models currently in the registry.
  ///
  /// Returns: A list of all [CactusModel] instances.
  static Future<List<CactusModel>> fetchModels() async {
    final registry = await getRegistry();
    return registry.values.toList();
  }

  /// Looks up a single model by its [slug].
  ///
  /// Returns: The matching [CactusModel], or `null` if no model with that slug
  /// exists in the registry.
  static Future<CactusModel?> getModel(String slug) async {
    final registry = await getRegistry();
    return registry[slug];
  }

  /// Resolves the latest compatible version tag for a given Hugging Face
  /// [modelId] by comparing git tags against the current runtime version.
  ///
  /// Tags are parsed as [SemverVersion] and the highest tag that is less than
  /// or equal to the runtime version is selected.
  /// Returns: The version tag string (e.g. `"v1.2.3"`).
  /// Throws: [Exception] if no compatible version is found.
  static Future<String> resolveVersion(String modelId) async {
    final client = _createClient();
    try {
      final uri = Uri.parse('https://huggingface.co/api/models/$modelId/refs');
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to fetch refs for $modelId: ${response.statusCode}');
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final tags = (data['tags'] as List<dynamic>?) ?? [];

      final runtimeVersion = _parseSemver(packageVersion);
      if (runtimeVersion == null) {
        throw Exception('Cannot parse runtime version: $packageVersion');
      }

      final compatible = <MapEntry<String, SemverVersion>>[];
      for (final tag in tags) {
        final tagName = (tag as Map<String, dynamic>)['name'] as String?;
        if (tagName == null) continue;
        final sv = _parseSemver(tagName.replaceFirst(RegExp(r'^v'), ''));
        if (sv != null && sv <= runtimeVersion) {
          compatible.add(MapEntry(tagName, sv));
        }
      }

      if (compatible.isEmpty) {
        throw Exception(
            'No compatible version found for $modelId (runtime: v$packageVersion)');
      }

      compatible.sort((a, b) => a.value.compareTo(b.value));
      return compatible.last.key;
    } finally {
      client.close();
    }
  }

  /// Constructs the download URL for a model's weight files on Hugging Face.
  ///
  /// [repoId]: The Hugging Face repository ID (e.g. `"org/model"`).
  /// [version]: The version tag (e.g. `"v1.0.0"`).
  /// [key]: The weight file key.
  /// [quantization]: The quantization level (e.g. `"int4"` or `"int8"`).
  /// [apple]: Whether to use the Apple-specific weight suffix.
  /// Returns: A fully-qualified HTTPS URL to the weight archive.
  static String constructDownloadUrl({
    required String repoId,
    required String version,
    required String key,
    required String quantization,
    bool apple = false,
  }) {
    final suffix = apple ? '-apple' : '';
    return 'https://huggingface.co/$repoId/resolve/$version/weights/$key-$quantization$suffix.zip';
  }

  static Future<Map<String, CactusModel>> _fetchRegistry() async {
    final client = _createClient();
    try {
      final org = CactusConfig.huggingFaceOrg;
      final uri =
          Uri.parse('https://huggingface.co/api/models?author=$org&full=true');
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to fetch HuggingFace registry: ${response.statusCode}');
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final List<dynamic> repos = jsonDecode(responseBody) as List<dynamic>;

      final Map<String, CactusModel> registry = {};

      final futures = <Future<_RepoParseResult?>>[];
      for (final repo in repos) {
        final repoMap = repo as Map<String, dynamic>;
        futures.add(_parseRepoToModel(repoMap));
      }

      final results = await Future.wait(futures);
      for (final result in results) {
        if (result != null) {
          registry[result.model.slug] = result.model;
        }
      }

      return registry;
    } finally {
      client.close();
    }
  }

  static Future<_RepoParseResult?> _parseRepoToModel(
      Map<String, dynamic> repo) async {
    final repoId = repo['id'] as String;
    final siblings = (repo['siblings'] as List<dynamic>?) ?? [];
    final tags = (repo['tags'] as List<dynamic>?) ?? [];

    final fileNames = siblings
        .map((s) => (s as Map<String, dynamic>)['rfilename'] as String?)
        .whereType<String>()
        .toList();

    final int4File = fileNames
        .where((f) => f.startsWith('weights/') && f.endsWith('-int4.zip'))
        .toList();
    final int8File = fileNames
        .where((f) => f.startsWith('weights/') && f.endsWith('-int8.zip'))
        .toList();

    if (int4File.isEmpty && int8File.isEmpty) return null;

    String key;
    {
      final int4Path = int4File.first;
      final filename = int4Path.split('/').last;
      key = filename.replaceAll(RegExp(r'-int4\.zip$'), '');
    }

    final capabilities =
        tags.whereType<String>().where(_kKnownCapabilities.contains).toList();

    String version;
    try {
      version = await resolveVersion(repoId);
    } catch (e) {
      debugPrint('Skipping $repoId: version resolution failed: $e');
      return null;
    }

    final Map<String, CactusQuantizationInfo> quantMap = {};

    for (final quant in ['int4', 'int8']) {
      final matchingFiles = quant == 'int4' ? int4File : int8File;
      if (matchingFiles.isEmpty) continue;

      final url = constructDownloadUrl(
        repoId: repoId,
        version: version,
        key: key,
        quantization: quant,
      );

      final appleFile = fileNames
          .where((f) =>
              f.startsWith('weights/') && f.endsWith('-$quant-apple.zip'))
          .toList();

      CactusProInfo? proInfo;
      if (appleFile.isNotEmpty) {
        final appleUrl = constructDownloadUrl(
          repoId: repoId,
          version: version,
          key: key,
          quantization: quant,
          apple: true,
        );
        proInfo = CactusProInfo(apple: appleUrl);
      }

      int sizeMb = 0;
      try {
        sizeMb = await _fetchFileSize(repoId, version, '$key-$quant.zip');
      } catch (e) {
        debugPrint('Failed to fetch size for $repoId/$quant: $e');
      }

      quantMap[quant] = CactusQuantizationInfo(
        sizeMb: sizeMb,
        url: url,
        pro: proInfo,
      );
    }

    final model = CactusModel(
      slug: key,
      name: key,
      capabilities: capabilities,
      quantization: quantMap,
    );

    return _RepoParseResult(model: model);
  }

  static Future<int> _fetchFileSize(
      String repoId, String version, String filename) async {
    final client = _createClient();
    try {
      final uri = Uri.parse(
          'https://huggingface.co/api/models/$repoId/tree/$version/weights');
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) return 0;

      final responseBody = await response.transform(utf8.decoder).join();
      final List<dynamic> files = jsonDecode(responseBody) as List<dynamic>;

      for (final file in files) {
        final fileMap = file as Map<String, dynamic>;
        final path = fileMap['path'] as String?;
        if (path != null && path.endsWith(filename)) {
          final size = fileMap['size'];
          if (size is int) return (size / (1024 * 1024)).round();
        }
      }

      return 0;
    } finally {
      client.close();
    }
  }

  static HttpClient _createClient() => HttpClient();

  /// Parses a [version] string in `major.minor.patch` format into a
  /// [SemverVersion]. Patch is treated as `0` when absent.
  ///
  /// Returns: A [SemverVersion] if parsing succeeds, or `null` if the string
  /// does not match the expected format.
  @visibleForTesting
  static SemverVersion? parseSemver(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?$').firstMatch(version);
    if (match == null) return null;
    return SemverVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      match.group(3) != null ? int.parse(match.group(3)!) : 0,
    );
  }

  static SemverVersion? _parseSemver(String version) => parseSemver(version);

  /// Extracts known capability strings from a list of [tags].
  ///
  /// Only tags that match the internal set of known capability identifiers are
  /// included in the result.
  /// Returns: A filtered list of capability strings.
  @visibleForTesting
  static List<String> extractCapabilities(List<dynamic> tags) {
    return tags
        .whereType<String>()
        .where(_kKnownCapabilities.contains)
        .toList();
  }
}

/// A simple semantic versioning representation that supports comparison.
class SemverVersion implements Comparable<SemverVersion> {
  /// The major version number.
  final int major;

  /// The minor version number.
  final int minor;

  /// The patch version number.
  final int patch;

  /// Creates a [SemverVersion] from [major], [minor], and [patch] components.
  const SemverVersion(this.major, this.minor, this.patch);

  /// Compares this version to [other], returning a negative, zero, or positive
  /// value if this version is less than, equal to, or greater than [other].
  @override
  int compareTo(SemverVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  /// Returns `true` if this version is less than or equal to [other].
  bool operator <=(SemverVersion other) => compareTo(other) <= 0;

  /// Returns a string representation in `major.minor.patch` format.
  @override
  String toString() => '$major.$minor.$patch';
}

class _RepoParseResult {
  final CactusModel model;
  const _RepoParseResult({required this.model});
}
