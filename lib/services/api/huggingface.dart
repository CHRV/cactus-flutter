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
  'diarization',
  'apple-npu',
};

class HuggingFace {
  static Future<Map<String, CactusModel>>? _registryCache;

  static Future<Map<String, CactusModel>> getRegistry() async {
    return _registryCache ??= _fetchRegistry();
  }

  static Future<Map<String, CactusModel>> refreshRegistry() async {
    _registryCache = null;
    return getRegistry();
  }

  static Future<List<CactusModel>> fetchModels() async {
    final registry = await getRegistry();
    return registry.values.toList();
  }

  static Future<CactusModel?> getModel(String slug) async {
    final registry = await getRegistry();
    return registry[slug];
  }

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

  @visibleForTesting
  static List<String> extractCapabilities(List<dynamic> tags) {
    return tags
        .whereType<String>()
        .where(_kKnownCapabilities.contains)
        .toList();
  }
}

class SemverVersion implements Comparable<SemverVersion> {
  final int major;
  final int minor;
  final int patch;

  const SemverVersion(this.major, this.minor, this.patch);

  @override
  int compareTo(SemverVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <=(SemverVersion other) => compareTo(other) <= 0;

  @override
  String toString() => '$major.$minor.$patch';
}

class _RepoParseResult {
  final CactusModel model;
  const _RepoParseResult({required this.model});
}
