import 'dart:async';
import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';

class DownloadPanel extends StatefulWidget {
  final DownloadHandle handle;
  final VoidCallback? onCompleted;
  final VoidCallback? onCancelled;
  final VoidCallback? onFailed;

  const DownloadPanel({
    super.key,
    required this.handle,
    this.onCompleted,
    this.onCancelled,
    this.onFailed,
  });

  @override
  State<DownloadPanel> createState() => _DownloadPanelState();
}

class _DownloadPanelState extends State<DownloadPanel> {
  DownloadProgress _lastProgress = const DownloadProgress();
  StreamSubscription<DownloadProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.handle.progressStream.listen(_onProgress);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onProgress(DownloadProgress p) {
    if (!mounted) return;
    setState(() => _lastProgress = p);
    if (p.status == DownloadStatus.completed) {
      widget.onCompleted?.call();
    } else if (p.status == DownloadStatus.cancelled) {
      widget.onCancelled?.call();
    } else if (p.status == DownloadStatus.failed) {
      widget.onFailed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _lastProgress;
    final isActive = p.status == DownloadStatus.downloading ||
        p.status == DownloadStatus.paused;
    final showPause = p.status == DownloadStatus.downloading;
    final showResume = p.status == DownloadStatus.paused;
    final showCancel = isActive || p.status == DownloadStatus.pending;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.statusMessage.isNotEmpty
                      ? p.statusMessage
                      : _statusLabel(p.status),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: _statusColor(p.status),
                  ),
                ),
              ),
              if (p.progress != null)
                Text(
                  '${(p.progress! * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (p.progress != null)
            LinearProgressIndicator(
              value: p.progress!.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                p.status == DownloadStatus.paused ? Colors.orange : Colors.black,
              ),
            )
          else
            const LinearProgressIndicator(backgroundColor: Colors.grey),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${p.receivedFormatted}${p.totalBytes > 0 ? ' / ${p.totalFormatted}' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(width: 12),
              if (p.speedBytesPerSec > 0)
                Text(
                  p.speedFormatted,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              const Spacer(),
              if (showPause)
                _button(Icons.pause, 'Pause', Colors.orange, () {
                  widget.handle.pause();
                }),
              if (showResume)
                _button(Icons.play_arrow, 'Resume', Colors.green, () {
                  widget.handle.pause();
                }),
              if (showCancel)
                _button(Icons.cancel, 'Cancel', Colors.red, () {
                  widget.handle.cancel();
                }),
            ],
          ),
          if (p.errorMessage != null && p.errorMessage!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                p.errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                tooltip,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(DownloadStatus status) => switch (status) {
    DownloadStatus.pending => 'Waiting...',
    DownloadStatus.downloading => 'Downloading...',
    DownloadStatus.paused => 'Paused',
    DownloadStatus.completed => 'Completed',
    DownloadStatus.failed => 'Failed',
    DownloadStatus.cancelled => 'Cancelled',
  };

  Color _statusColor(DownloadStatus status) => switch (status) {
    DownloadStatus.downloading => Colors.black,
    DownloadStatus.paused => Colors.orange,
    DownloadStatus.completed => Colors.green,
    DownloadStatus.failed => Colors.red,
    DownloadStatus.cancelled => Colors.grey,
    DownloadStatus.pending => Colors.grey,
  };
}
