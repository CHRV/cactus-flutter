import 'dart:typed_data';

class AudioInput {
  final String? filePath;
  final Uint8List? pcmData;

  AudioInput({this.filePath, this.pcmData});

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