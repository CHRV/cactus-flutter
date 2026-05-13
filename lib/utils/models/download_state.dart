import 'dart:async';

enum DownloadStatus { pending, downloading, paused, completed, failed, cancelled }

class DownloadProgress {
  final double? progress;
  final int bytesReceived;
  final int totalBytes;
  final double speedBytesPerSec;
  final String statusMessage;
  final DownloadStatus status;
  final String? errorMessage;

  const DownloadProgress({
    this.progress,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.statusMessage = '',
    this.status = DownloadStatus.pending,
    this.errorMessage,
  });

  String get speedFormatted {
    final speed = speedBytesPerSec;
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get receivedFormatted {
    if (bytesReceived < 1024 * 1024) {
      return '${(bytesReceived / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytesReceived / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get totalFormatted {
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class DownloadHandle {
  final String id;
  final String url;
  final String filename;
  final String folder;

  void Function()? onCancel;
  void Function()? onPause;

  final StreamController<DownloadProgress> _controller =
      StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _controller.stream;

  DownloadHandle({
    required this.id,
    required this.url,
    required this.filename,
    required this.folder,
  });

  void cancel() => onCancel?.call();

  void pause() => onPause?.call();

  void emit(DownloadProgress progress) {
    if (!_controller.isClosed) {
      _controller.add(progress);
    }
  }

  void close() {
    _controller.close();
  }
}
