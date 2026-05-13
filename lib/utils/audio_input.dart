import 'dart:typed_data';

/// Represents audio input as either a file path or raw PCM bytes.
///
/// Exactly one of [filePath] or [pcmData] should be provided.
class AudioInput {
  /// Path to an audio file on disk.
  final String? filePath;

  /// Raw PCM audio data.
  final Uint8List? pcmData;

  /// Creates an [AudioInput] from an optional [filePath] or [pcmData].
  ///
  /// [filePath]: Path to an audio file.
  /// [pcmData]: Raw PCM audio bytes.
  AudioInput({this.filePath, this.pcmData});

  /// Converts a dynamic value into an [AudioInput].
  ///
  /// If [audio] is a [String] it is treated as a file path.
  /// If [audio] is a [List<int>] it is treated as PCM data.
  ///
  /// [audio]: The value to resolve — a `String` (file path) or `List<int>` (PCM data).
  /// Returns: An [AudioInput] wrapping the provided audio source.
  /// Throws: [ArgumentError] if [audio] is neither a String nor a List<int>.
  static AudioInput resolve(dynamic audio) {
    if (audio is String) {
      return AudioInput(filePath: audio);
    } else if (audio is List<int>) {
      return AudioInput(pcmData: audio is Uint8List ? audio : Uint8List.fromList(audio));
    } else {
      throw ArgumentError('audio must be a String (filepath) or List<int> (PCM data)');
    }
  }
}
