typedef CactusTokenCallback = bool Function(String token);
typedef CactusProgressCallback = void Function(double? progress, String statusMessage, bool isError);

class CactusModelOptions {
  final String quantization;
  final bool pro;

  const CactusModelOptions({
    this.quantization = 'int8',
    this.pro = false,
  });
}

class CactusLMMessage {
  final String role;
  final String? content;
  final List<String> images;

  CactusLMMessage({
    required this.role,
    this.content,
    this.images = const [],
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    if (content != null) 'content': content,
    if (images.isNotEmpty) 'images': images,
  };
}

class CactusLMTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  CactusLMTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'parameters': parameters,
  };
}

class FunctionCall {
  final String name;
  final Map<String, dynamic> arguments;

  FunctionCall({required this.name, required this.arguments});
}

class CactusLMCompleteOptions {
  final double? temperature;
  final int? topK;
  final double? topP;
  final int maxTokens;
  final List<String> stopSequences;
  final bool? forceTools;
  final bool? telemetryEnabled;
  final double? confidenceThreshold;
  final bool? includeStopSequences;
  final bool? enableThinking;

  const CactusLMCompleteOptions({
    this.temperature,
    this.topK,
    this.topP,
    this.maxTokens = 512,
    this.stopSequences = const ['<|im_end|>', '<end_of_turn>'],
    this.forceTools,
    this.telemetryEnabled,
    this.confidenceThreshold,
    this.includeStopSequences,
    this.enableThinking,
  });
}

class CactusLMCompleteResult {
  final bool success;
  final String response;
  final String? thinking;
  final List<FunctionCall>? functionCalls;
  final bool? cloudHandoff;
  final double? confidence;
  final double timeToFirstTokenMs;
  final double totalTimeMs;
  final int prefillTokens;
  final double prefillTps;
  final int decodeTokens;
  final double decodeTps;
  final int totalTokens;
  final double? ramUsageMb;

  CactusLMCompleteResult({
    required this.success,
    required this.response,
    this.thinking,
    this.functionCalls,
    this.cloudHandoff,
    this.confidence,
    required this.timeToFirstTokenMs,
    required this.totalTimeMs,
    required this.prefillTokens,
    required this.prefillTps,
    required this.decodeTokens,
    required this.decodeTps,
    required this.totalTokens,
    this.ramUsageMb,
  });
}

class CactusLMEmbedResult {
  final List<double> embedding;

  CactusLMEmbedResult({required this.embedding});
}

class CactusLMImageEmbedResult {
  final List<double> embedding;

  CactusLMImageEmbedResult({required this.embedding});
}

class CactusLMPrefillResult {
  final bool success;
  final String? error;
  final int prefillTokens;
  final double prefillTps;
  final double totalTimeMs;
  final double ramUsageMb;

  CactusLMPrefillResult({
    required this.success,
    this.error,
    this.prefillTokens = 0,
    this.prefillTps = 0.0,
    this.totalTimeMs = 0.0,
    this.ramUsageMb = 0.0,
  });
}

class CactusLMTokenizeResult {
  final List<int> tokens;

  CactusLMTokenizeResult({required this.tokens});
}

class CactusLMScoreWindowResult {
  final double score;

  CactusLMScoreWindowResult({required this.score});
}

class RagQueryChunk {
  final double score;
  final String source;
  final String content;

  RagQueryChunk({required this.score, required this.source, required this.content});
}

class CactusLMRagQueryResult {
  final List<RagQueryChunk> chunks;
  final String? error;

  CactusLMRagQueryResult({this.chunks = const [], this.error});
}

class CactusSTTTranscribeOptions {
  final double? temperature;
  final int? topK;
  final double? topP;
  final int maxTokens;
  final List<String> stopSequences;
  final bool? useVad;
  final bool? telemetryEnabled;
  final double? confidenceThreshold;
  final double? cloudHandoffThreshold;
  final bool? includeStopSequences;

  const CactusSTTTranscribeOptions({
    this.temperature,
    this.topK,
    this.topP,
    this.maxTokens = 384,
    this.stopSequences = const ['<|startoftranscript|>'],
    this.useVad,
    this.telemetryEnabled,
    this.confidenceThreshold,
    this.cloudHandoffThreshold,
    this.includeStopSequences,
  });
}

class CactusSTTTranscribeResult {
  final bool success;
  final String response;
  final bool? cloudHandoff;
  final double? confidence;
  final double timeToFirstTokenMs;
  final double totalTimeMs;
  final int prefillTokens;
  final double prefillTps;
  final int decodeTokens;
  final double decodeTps;
  final int totalTokens;
  final double? ramUsageMb;

  CactusSTTTranscribeResult({
    required this.success,
    required this.response,
    this.cloudHandoff,
    this.confidence,
    required this.timeToFirstTokenMs,
    required this.totalTimeMs,
    required this.prefillTokens,
    required this.prefillTps,
    required this.decodeTokens,
    required this.decodeTps,
    required this.totalTokens,
    this.ramUsageMb,
  });
}

class CactusSTTAudioEmbedResult {
  final List<double> embedding;

  CactusSTTAudioEmbedResult({required this.embedding});
}

class CactusSTTStreamTranscribeStartOptions {
  final double? confirmationThreshold;
  final int? minChunkSize;
  final bool? telemetryEnabled;
  final String? language;

  const CactusSTTStreamTranscribeStartOptions({
    this.confirmationThreshold,
    this.minChunkSize,
    this.telemetryEnabled,
    this.language,
  });
}

class CactusSTTStreamTranscribeProcessResult {
  final bool success;
  final String confirmed;
  final String pending;
  final double? bufferDurationMs;
  final double? confidence;
  final bool? cloudHandoff;
  final double? timeToFirstTokenMs;
  final double? totalTimeMs;
  final int? prefillTokens;
  final double? prefillTps;
  final int? decodeTokens;
  final double? decodeTps;
  final int? totalTokens;
  final double? ramUsageMb;

  CactusSTTStreamTranscribeProcessResult({
    required this.success,
    required this.confirmed,
    required this.pending,
    this.bufferDurationMs,
    this.confidence,
    this.cloudHandoff,
    this.timeToFirstTokenMs,
    this.totalTimeMs,
    this.prefillTokens,
    this.prefillTps,
    this.decodeTokens,
    this.decodeTps,
    this.totalTokens,
    this.ramUsageMb,
  });
}

class CactusSTTStreamTranscribeStopResult {
  final bool success;
  final String confirmed;

  CactusSTTStreamTranscribeStopResult({required this.success, required this.confirmed});
}

class CactusSTTDetectLanguageResult {
  final String language;
  final double? confidence;

  CactusSTTDetectLanguageResult({required this.language, this.confidence});
}

class CactusSTTDetectLanguageOptions {
  final bool? useVad;

  const CactusSTTDetectLanguageOptions({this.useVad});
}

class CactusAudioVADOptions {
  final double? threshold;
  final double? negThreshold;
  final int? minSpeechDurationMs;
  final double? maxSpeechDurationS;
  final int? minSilenceDurationMs;
  final int? speechPadMs;
  final int? windowSizeSamples;
  final int? samplingRate;
  final int? minSilenceAtMaxSpeech;
  final bool? useMaxPossSilAtMaxSpeech;

  const CactusAudioVADOptions({
    this.threshold,
    this.negThreshold,
    this.minSpeechDurationMs,
    this.maxSpeechDurationS,
    this.minSilenceDurationMs,
    this.speechPadMs,
    this.windowSizeSamples,
    this.samplingRate,
    this.minSilenceAtMaxSpeech,
    this.useMaxPossSilAtMaxSpeech,
  });
}

class CactusAudioVADSegment {
  final int start;
  final int end;

  CactusAudioVADSegment({required this.start, required this.end});
}

class CactusAudioVADResult {
  final List<CactusAudioVADSegment> segments;
  final double totalTime;
  final double ramUsage;

  CactusAudioVADResult({this.segments = const [], required this.totalTime, required this.ramUsage});
}

class CactusAudioDiarizeOptions {
  final int? stepMs;
  final double? threshold;
  final int? numSpeakers;
  final int? minSpeakers;
  final int? maxSpeakers;

  const CactusAudioDiarizeOptions({
    this.stepMs,
    this.threshold,
    this.numSpeakers,
    this.minSpeakers,
    this.maxSpeakers,
  });
}

class CactusAudioDiarizeResult {
  final bool success;
  final String? error;
  final int numSpeakers;
  final List<double> scores;
  final double totalTimeMs;
  final double ramUsageMb;

  CactusAudioDiarizeResult({
    required this.success,
    this.error,
    this.numSpeakers = 0,
    this.scores = const [],
    this.totalTimeMs = 0.0,
    this.ramUsageMb = 0.0,
  });
}

class CactusAudioEmbedSpeakerOptions {
  final int? stepMs;
  final double? threshold;
  final List<double>? maskWeights;
  final int? maskNumFrames;

  const CactusAudioEmbedSpeakerOptions({
    this.stepMs,
    this.threshold,
    this.maskWeights,
    this.maskNumFrames,
  });
}

class CactusAudioEmbedSpeakerResult {
  final bool success;
  final String? error;
  final List<double> embedding;
  final double totalTimeMs;
  final double ramUsageMb;

  CactusAudioEmbedSpeakerResult({
    required this.success,
    this.error,
    this.embedding = const [],
    this.totalTimeMs = 0.0,
    this.ramUsageMb = 0.0,
  });
}

class CactusIndexGetResult {
  final List<String> documents;
  final List<String> metadatas;
  final List<List<double>> embeddings;

  CactusIndexGetResult({
    this.documents = const [],
    this.metadatas = const [],
    this.embeddings = const [],
  });
}

class CactusIndexQueryOptions {
  final int? topK;
  final double? scoreThreshold;

  const CactusIndexQueryOptions({this.topK, this.scoreThreshold});
}

class CactusIndexQueryResult {
  final List<List<int>> ids;
  final List<List<double>> scores;

  CactusIndexQueryResult({this.ids = const [], this.scores = const []});
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
