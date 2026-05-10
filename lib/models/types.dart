import 'tools.dart';

typedef CactusTokenCallback = bool Function(String token);
typedef CactusProgressCallback = void Function(double? progress, String statusMessage, bool isError);

class ChatMessage {
  final String content;
  final String role;
  final List<String> images;
  final List<String> audio;
  final int? timestamp;

  ChatMessage({
    required this.content,
    required this.role,
    this.images = const [],
    this.audio = const [],
    this.timestamp,
  });

  @override
  bool operator ==(Object other) => other is ChatMessage && role == other.role && content == other.content;
  
  @override
  int get hashCode => role.hashCode ^ content.hashCode;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (timestamp != null) 'timestamp': timestamp,
  };
}

class CactusCompletionParams {
  final String? model;
  final double? temperature;
  final int? topK;
  final double? topP;
  final int maxTokens;
  final List<String> stopSequences;
  final List<CactusTool>? tools;
  final CompletionMode completionMode;
  final String? cactusToken;
  final bool? forceTools;

  CactusCompletionParams({
    this.model,
    this.temperature,
    this.topK,
    this.topP,
    this.maxTokens = 512,
    this.stopSequences = const ["<|im_end|>", "<end_of_turn>"],
    this.tools,
    this.completionMode = CompletionMode.local,
    this.cactusToken,
    this.forceTools,
  });
}

class CactusCompletionResult {
  final bool success;
  final String response;
  final double confidence;
  final bool cloudHandoff;
  final String? thinking;
  final double timeToFirstTokenMs;
  final double totalTimeMs;
  final double tokensPerSecond;
  final double prefillTps;
  final double decodeTps;
  final double ramUsageMb;
  final int prefillTokens;
  final int decodeTokens;
  final int totalTokens;
  final List<ToolCall> toolCalls;

  CactusCompletionResult({
    required this.success,
    required this.response,
    this.confidence = 0.0,
    this.cloudHandoff = false,
    this.thinking,
    required this.timeToFirstTokenMs,
    required this.totalTimeMs,
    required this.tokensPerSecond,
    this.prefillTps = 0.0,
    this.decodeTps = 0.0,
    this.ramUsageMb = 0.0,
    required this.prefillTokens,
    required this.decodeTokens,
    required this.totalTokens,
    this.toolCalls = const [],
  });
}

class CactusException implements Exception {
  final String message;
  final dynamic underlyingError;

  CactusException(this.message, [this.underlyingError]);

  @override
  String toString() {
    if (underlyingError != null) {
      return 'CactusException: $message (Caused by: $underlyingError)';
    }
    return 'CactusException: $message';
  }
}

class CactusInitParams {
  final String model;
  final int? contextSize;
  final String? corpusDir;
  final bool cacheIndex;

  CactusInitParams({
    this.model = "qwen3-0.6",
    this.contextSize,
    this.corpusDir,
    this.cacheIndex = false,
  });
}

class CactusStreamedCompletionResult {
  final Stream<String> stream;
  final Future<CactusCompletionResult> result;

  CactusStreamedCompletionResult({required this.stream, required this.result});
}

class CactusEmbeddingResult {
  final bool success;
  final List<double> embeddings;
  final int dimension;
  final String? errorMessage;

  CactusEmbeddingResult({
    required this.success,
    required this.embeddings,
    required this.dimension,
    this.errorMessage,
  });
}

class CactusTranscriptionParams {
  final int maxTokens;
  final List<String> stopSequences;

  CactusTranscriptionParams({
    this.maxTokens = 2048,
    this.stopSequences = const ["<|startoftranscript|>"],
  });
}

class CactusTranscriptionResult {
  final bool success;
  final String text;
  final double confidence;
  final bool cloudHandoff;
  final List<TranscriptionSegment> segments;
  final double timeToFirstTokenMs;
  final double totalTimeMs;
  final double tokensPerSecond;
  final String? errorMessage;

  CactusTranscriptionResult({
    required this.success,
    required this.text,
    this.confidence = 0.0,
    this.cloudHandoff = false,
    this.segments = const [],
    this.timeToFirstTokenMs = 0.0,
    this.totalTimeMs = 0.0,
    this.tokensPerSecond = 0.0,
    this.errorMessage,
  });
}

class TranscriptionSegment {
  final double start;
  final double end;
  final String text;

  TranscriptionSegment({
    required this.start,
    required this.end,
    required this.text,
  });
}

class CactusStreamedTranscriptionResult {
  final Stream<String> stream;
  final Future<CactusTranscriptionResult> result;

  CactusStreamedTranscriptionResult({required this.stream, required this.result});
}

class CactusProInfo {
  final String apple;

  CactusProInfo({required this.apple});

  factory CactusProInfo.fromJson(Map<String, dynamic> json) {
    return CactusProInfo(apple: json['apple'] as String);
  }

  Map<String, dynamic> toJson() => {'apple': apple};
}

class CactusQuantizationInfo {
  final int sizeMb;
  final String url;
  final CactusProInfo? pro;

  CactusQuantizationInfo({
    required this.sizeMb,
    required this.url,
    this.pro,
  });

  factory CactusQuantizationInfo.fromJson(Map<String, dynamic> json) {
    return CactusQuantizationInfo(
      sizeMb: json['size_mb'] as int,
      url: json['url'] as String,
      pro: json['pro'] != null
          ? CactusProInfo.fromJson(json['pro'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'size_mb': sizeMb,
    'url': url,
    if (pro != null) 'pro': pro!.toJson(),
  };
}

class CactusModel {
  final String slug;
  final String name;
  final List<String> capabilities;
  final Map<String, CactusQuantizationInfo> quantization;
  bool isDownloaded;

  DateTime? _createdAt;

  CactusModel({
    required this.slug,
    required this.name,
    required this.capabilities,
    required this.quantization,
    this.isDownloaded = false,
    DateTime? createdAt,
  }) : _createdAt = createdAt;

  String get downloadUrl => quantization['int4']?.url ?? '';
  bool get supportsToolCalling => capabilities.contains('tools');
  bool get supportsVision => capabilities.contains('vision');
  int get sizeMb => quantization['int4']?.sizeMb ?? 0;
  DateTime get createdAt => _createdAt ?? DateTime(2000);

  factory CactusModel.fromJson(Map<String, dynamic> json) {
    final Map<String, CactusQuantizationInfo> quantMap = {};
    final quantJson = json['quantization'] as Map<String, dynamic>?;
    if (quantJson != null) {
      for (final entry in quantJson.entries) {
        quantMap[entry.key] = CactusQuantizationInfo.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return CactusModel(
      slug: json['slug'] as String,
      name: json['name'] as String? ?? json['slug'] as String,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      quantization: quantMap,
      isDownloaded: json['is_downloaded'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'name': name,
    'capabilities': capabilities,
    'quantization': quantization.map((k, v) => MapEntry(k, v.toJson())),
    'is_downloaded': isDownloaded,
    if (_createdAt != null) 'created_at': _createdAt!.toIso8601String(),
  };
}

enum CompletionMode {
  local,
  hybrid
}

enum TranscriptionProvider {
  whisper
}

class VoiceModel {
  final DateTime createdAt;
  final String slug;
  final String downloadUrl;
  final int sizeMb;
  final String fileName;
  bool isDownloaded;

  VoiceModel({
    required this.createdAt,
    required this.slug,
    required this.downloadUrl,
    required this.sizeMb,
    required this.fileName,
    this.isDownloaded = false,
  });

  factory VoiceModel.fromJson(Map<String, dynamic> json) {
    return VoiceModel(
      createdAt: DateTime.parse(json['created_at'] as String),
      slug: json['slug'] as String,
      downloadUrl: json['download_url'] as String,
      sizeMb: _parseIntFromDynamic(json['size_mb']),
      fileName: json['file_name'] as String,
      isDownloaded: false,
    );
  }

  static int _parseIntFromDynamic(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.parse(value);
    throw FormatException('Cannot parse $value as int');
  }
}

class SpeechRecognitionParams {
  final int sampleRate;
  final int maxDuration;
  final String? model;

  SpeechRecognitionParams({
    this.sampleRate = 16000,
    this.maxDuration = 30000,
    this.model,
  });
}

class SpeechRecognitionResult {
  final bool success;
  final String text;
  final double? processingTime;

  SpeechRecognitionResult({
    required this.success,
    required this.text,
    this.processingTime
  });
}

class STTInitParams {
  final String model;

  STTInitParams({
    required this.model,
  });
}

class PrefillResult {
  final bool success;
  final int prefillTokens;
  final double prefillTps;
  final double totalTimeMs;
  final double ramUsageMb;
  final String? errorMessage;

  PrefillResult({
    required this.success,
    this.prefillTokens = 0,
    this.prefillTps = 0.0,
    this.totalTimeMs = 0.0,
    this.ramUsageMb = 0.0,
    this.errorMessage,
  });
}

class DetectLanguageResult {
  final String language;
  final double confidence;
  final String languageToken;

  DetectLanguageResult({
    required this.language,
    this.confidence = 0.0,
    this.languageToken = '',
  });
}

class VadResult {
  final List<VadSegment> segments;
  final double totalTimeMs;

  VadResult({
    this.segments = const [],
    this.totalTimeMs = 0.0,
  });
}

class VadSegment {
  final int start;
  final int end;

  VadSegment({
    required this.start,
    required this.end,
  });
}

class DiarizeResult {
  final int numSpeakers;
  final List<double> scores;
  final double totalTimeMs;

  DiarizeResult({
    this.numSpeakers = 0,
    this.scores = const [],
    this.totalTimeMs = 0.0,
  });
}

class SpeakerEmbeddingResult {
  final List<double> embedding;
  final double totalTimeMs;

  SpeakerEmbeddingResult({
    this.embedding = const [],
    this.totalTimeMs = 0.0,
  });
}