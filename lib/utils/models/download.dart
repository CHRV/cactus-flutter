import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:cactus/models/types.dart';
import 'package:cactus/utils/models/download_state.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DownloadTask {
  final String url;
  final String filename;
  final String folder;

  DownloadTask({
    required this.url,
    required this.filename,
    required this.folder,
  });
}

class ResumableDownloadService {
  ResumableDownloadService._();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    dio.interceptors.add(RetryInterceptor(
      dio: dio,
      retries: 3,
      retryDelays: const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ],
      retryableExtraStatuses: {408, 429, 500, 502, 503, 504},
    ));
    return dio;
  }

  static String _downloadId(String url) {
    final bytes = utf8.encode(url);
    return base64Url.encode(bytes).replaceAll('=', '').substring(0, 32);
  }

  static Future<Directory> _stateDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/.cactus_downloads');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<String> _stateFilePath(String id) async {
    final dir = await _stateDir();
    return '${dir.path}/$id.json';
  }

  static Future<Map<String, dynamic>?> _loadState(String id) async {
    try {
      final file = File(await _stateFilePath(id));
      if (await file.exists()) {
        return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _saveState(
      String id, Map<String, dynamic> state) async {
    try {
      final file = File(await _stateFilePath(id));
      await file.writeAsString(jsonEncode(state));
    } catch (e) {
      debugPrint('Failed to save download state: $e');
    }
  }

  static Future<void> _deleteState(String id) async {
    try {
      final file = File(await _stateFilePath(id));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<DownloadHandle> download({
    required String url,
    required String filename,
    required String folder,
    void Function(DownloadProgress)? onProgress,
    String? basePath,
  }) async {
    final id = _downloadId(url);
    final handle = DownloadHandle(
      id: id,
      url: url,
      filename: filename,
      folder: folder,
    );

    _startDownload(handle, onProgress, basePath);
    return handle;
  }

  static Future<void> _startDownload(
    DownloadHandle handle,
    void Function(DownloadProgress)? onProgress,
    String? basePath,
  ) async {
    int currentBytes = 0;
    int currentTotal = 0;
    String? currentEtag;
    bool isPaused = false;
    bool isCancelled = false;

    final appDocDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(basePath ?? '${appDocDir.path}/models');
    await modelsDir.create(recursive: true);

    final partFilePath = '${modelsDir.path}/${handle.filename}.cpart';
    final modelFolderPath = basePath != null
        ? '$basePath/${handle.folder}'
        : '${appDocDir.path}/models/${handle.folder}';

    final dio = _createDio();
    final cancelToken = CancelToken();

    handle.onCancel = () {
      isCancelled = true;
      cancelToken.cancel();
    };

    handle.onPause = () async {
      isPaused = true;
      await _saveState(handle.id, {
        'url': handle.url,
        'filename': handle.filename,
        'folder': handle.folder,
        'bytes_downloaded': currentBytes,
        'total_bytes': currentTotal,
        'etag': currentEtag,
        'timestamp': DateTime.now().toIso8601String(),
      });
      cancelToken.cancel();
    };

    void emitProgress(DownloadStatus status, {String message = '', String? error}) {
      final p = currentTotal > 0
          ? DownloadProgress(
              progress: currentBytes / currentTotal,
              bytesReceived: currentBytes,
              totalBytes: currentTotal,
              statusMessage: message,
              status: status,
              errorMessage: error,
            )
          : DownloadProgress(
              bytesReceived: currentBytes,
              totalBytes: currentTotal,
              statusMessage: message,
              status: status,
              errorMessage: error,
            );
      handle.emit(p);
      onProgress?.call(p);
    }

    try {
      final savedState = await _loadState(handle.id);
      if (savedState != null) {
        currentBytes = savedState['bytes_downloaded'] as int? ?? 0;
        currentTotal = savedState['total_bytes'] as int? ?? 0;
        currentEtag = savedState['etag'] as String?;
      }

      IOSink? sink;
      if (currentBytes > 0) {
        final partFile = File(partFilePath);
        if (await partFile.exists()) {
          sink = partFile.openWrite(mode: FileMode.append);
        } else {
          currentBytes = 0;
          sink = File(partFilePath).openWrite();
        }
      } else {
        sink = File(partFilePath).openWrite();
      }

      final headers = <String, dynamic>{};
      if (currentBytes > 0) {
        headers['Range'] = 'bytes=$currentBytes-';
      }

      final response = await dio.get<ResponseBody>(
        handle.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers.isNotEmpty ? headers : null,
        ),
        cancelToken: cancelToken,
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode == 206 || statusCode == 200) {
        if (statusCode == 200 && currentBytes > 0) {
          currentBytes = 0;
          currentTotal = 0;
          await sink.close();
          sink = File(partFilePath).openWrite();
        }

        final body =
            response.data ?? (throw Exception('No response body'));
        {
          final clHeaders = body.headers['content-length'];
          if (clHeaders != null && clHeaders.isNotEmpty && currentTotal == 0) {
            currentTotal = currentBytes + int.parse(clHeaders.first);
          }
          final etagHeaders = body.headers['etag'];
          if (etagHeaders != null && etagHeaders.isNotEmpty) {
            currentEtag = etagHeaders.first;
          }
        }

        final stream = body.stream;
        int lastSaveBytes = currentBytes;

        await for (final chunk in stream) {
          if (cancelToken.isCancelled) break;
          sink.add(chunk);
          currentBytes += chunk.length;

          emitProgress(DownloadStatus.downloading,
              message: 'Downloaded ${currentBytes ~/ (1024 * 1024)} MB...');

          if (currentBytes - lastSaveBytes >= 1024 * 1024) {
            await _saveState(handle.id, {
              'url': handle.url,
              'filename': handle.filename,
              'folder': handle.folder,
              'bytes_downloaded': currentBytes,
              'total_bytes': currentTotal,
              'etag': currentEtag,
              'timestamp': DateTime.now().toIso8601String(),
            });
            lastSaveBytes = currentBytes;
          }
        }

        await sink.close();

        if (cancelToken.isCancelled) {
          if (isCancelled) {
            final pf = File(partFilePath);
            if (await pf.exists()) await pf.delete();
            await _deleteState(handle.id);
            emitProgress(DownloadStatus.cancelled, message: 'Download cancelled');
          } else {
            emitProgress(DownloadStatus.paused, message: 'Download paused');
          }
          handle.close();
          return;
        }

        await _deleteState(handle.id);

        emitProgress(DownloadStatus.completed,
            message: 'Download completed, extracting...');

        final modelFolder = Directory(modelFolderPath);
        final isZip = handle.filename.toLowerCase().endsWith('.zip');
        if (isZip) {
          await _extractZipFile(
              partFilePath, modelFolderPath, (progress, msg, isErr) {
            emitProgress(DownloadStatus.completed,
                message: msg, error: isErr ? msg : null);
          });
          final pf = File(partFilePath);
          if (await pf.exists()) await pf.delete();
        } else {
          await modelFolder.create(recursive: true);
          await File(partFilePath).rename('$modelFolderPath/${handle.filename}');
        }

        emitProgress(DownloadStatus.completed,
            message: 'Download completed successfully');
        debugPrint('Download completed: $modelFolderPath');
      } else {
        await sink.close();
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Unexpected status: $statusCode',
        );
      }
    } catch (e) {
      if (isCancelled) {
        emitProgress(DownloadStatus.cancelled, message: 'Download cancelled');
      } else if (isPaused) {
        emitProgress(DownloadStatus.paused, message: 'Download paused');
      } else {
        final errMsg = 'Download failed: $e';
        debugPrint(errMsg);
        emitProgress(DownloadStatus.failed, message: errMsg, error: errMsg);

        final pf = File(partFilePath);
        if (await pf.exists()) await pf.delete();
        final mf = Directory(modelFolderPath);
        if (await mf.exists()) {
          try {
            final files = await mf.list().toList();
            if (files.length < 5) await mf.delete(recursive: true);
          } catch (_) {}
        }
        await _deleteState(handle.id);
      }
    } finally {
      dio.close();
      handle.close();
    }
  }

  static Future<void> _extractZipFile(String zipFilePath, String extractToPath,
      CactusProgressCallback? onProgress) async {
    final modelFolder = Directory(extractToPath);
    await modelFolder.create(recursive: true);
    onProgress?.call(null, 'Extracting files...', false);

    final inputStream = InputFileStream(zipFilePath);

    try {
      final archive = ZipDecoder().decodeStream(inputStream);
      final symbolicLinks = <ArchiveFile>[];

      String? rootFolderName;
      for (final file in archive) {
        if (file.isFile || file.isDirectory) {
          final pathParts = file.name.split('/');
          if (pathParts.length > 1) {
            final candidate = pathParts.first;
            if (rootFolderName == null) {
              rootFolderName = candidate;
            } else if (rootFolderName != candidate) {
              rootFolderName = null;
              break;
            }
          } else {
            rootFolderName = null;
            break;
          }
        }
      }

      debugPrint('Root folder in archive: $rootFolderName');

      for (final file in archive) {
        if (file.isSymbolicLink) {
          symbolicLinks.add(file);
          continue;
        }

        String relativePath = file.name;
        if (rootFolderName != null &&
            relativePath.startsWith('$rootFolderName/')) {
          relativePath = relativePath.substring(rootFolderName.length + 1);
        }

        if (relativePath.isEmpty) continue;

        if (file.isFile) {
          final extractedFilePath = '$extractToPath/$relativePath';
          final extractedFileParent = File(extractedFilePath).parent;
          await extractedFileParent.create(recursive: true);
          final outputStream = OutputFileStream(extractedFilePath);
          file.writeContent(outputStream);
          outputStream.closeSync();
        } else {
          final dirPath = '$extractToPath/$relativePath';
          await Directory(dirPath).create(recursive: true);
        }
      }

      for (final file in symbolicLinks) {
        String relativePath = file.name;
        if (rootFolderName != null &&
            relativePath.startsWith('$rootFolderName/')) {
          relativePath = relativePath.substring(rootFolderName.length + 1);
        }
        if (relativePath.isNotEmpty) {
          final linkPath = '$extractToPath/$relativePath';
          final link = Link(linkPath);
          await link.create(file.symbolicLink!, recursive: true);
        }
      }
    } finally {
      inputStream.close();
    }
  }

  static Future<bool> modelExists(String folderName, [String? basePath]) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final modelFolderPath =
        basePath ?? '${appDocDir.path}/models/$folderName';
    final modelFolder = Directory(modelFolderPath);
    if (await modelFolder.exists()) {
      final files = await modelFolder.list().toList();
      return files.isNotEmpty;
    }
    return false;
  }

  static Future<DownloadHandle?> resumeSaved({String? basePath}) async {
    final dir = await _stateDir();
    final entries = dir.listSync().whereType<File>().toList();
    if (entries.isEmpty) return null;

    for (final file in entries) {
      try {
        final state =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final id = file.uri.pathSegments.last.replaceAll('.json', '');
        final bytesDownloaded = state['bytes_downloaded'] as int? ?? 0;

        final appDocDir = await getApplicationDocumentsDirectory();
        final modelsDir = Directory(basePath ?? '${appDocDir.path}/models');
        final partFilePath = '${modelsDir.path}/${state['filename']}.cpart';
        final partFile = File(partFilePath);

        if (!await partFile.exists() || bytesDownloaded == 0) {
          await file.delete();
          continue;
        }

        final handle = DownloadHandle(
          id: id,
          url: state['url'] as String,
          filename: state['filename'] as String,
          folder: state['folder'] as String,
        );
        _startDownload(handle, null, basePath);
        return handle;
      } catch (_) {
        await file.delete();
      }
    }
    return null;
  }

  static Future<bool> downloadAndExtractModels(
    List<DownloadTask> tasks,
    CactusProgressCallback? onProgress, [
    String? basePath,
  ]) async {
    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final progress = tasks.length > 1 ? i / tasks.length : null;
      onProgress?.call(progress, 'Downloading ${task.folder}...', false);

      final completer = Completer<bool>();
      await download(
        url: task.url,
        filename: task.filename,
        folder: task.folder,
        basePath: basePath,
        onProgress: (p) {
          if (p.status == DownloadStatus.completed) {
            onProgress?.call(1.0, 'Downloaded ${task.folder}', false);
            if (!completer.isCompleted) completer.complete(true);
          } else if (p.status == DownloadStatus.failed ||
              p.status == DownloadStatus.cancelled) {
            if (!completer.isCompleted) completer.complete(false);
          } else {
            onProgress?.call(
                p.progress, p.statusMessage, p.errorMessage != null);
          }
        },
      );

      final success = await completer.future;
      if (!success) return false;
    }

    onProgress?.call(1.0, 'All downloads completed successfully', false);
    return true;
  }
}
