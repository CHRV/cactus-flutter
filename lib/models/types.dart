import 'dart:async';

enum CompletionMode { local, cloud, hybrid }

typedef CactusTokenCallback = void Function(String token);
typedef CactusProgressCallback = void Function(
    double? progress, String statusMessage, bool isError);

typedef ChatMessage = CactusLMMessage;
typedef CactusCompletionParams = CactusLMCompleteOptions;
typedef CactusCompletionResult = CactusLMCompleteResult;
typedef CactusInitParams = CactusLMCompleteOptions;

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
  final CompletionMode? completionMode;
  final String? cactusToken;

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
    this.completionMode,
    this.cactusToken,
  });

  Map<String, dynamic> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (topK != null) 'top_k': topK,
        if (topP != null) 'top_p': topP,
        'max_tokens': maxTokens,
        'stop_sequences': stopSequences,
        if (forceTools != null) 'force_tools': forceTools,
        if (telemetryEnabled != null) 'telemetry_enabled': telemetryEnabled,
        if (confidenceThreshold != null)
          'confidence_threshold': confidenceThreshold,
        if (includeStopSequences != null)
          'include_stop_sequences': includeStopSequences,
        if (enableThinking != null) 'enable_thinking': enableThinking,
        if (completionMode != null) 'completion_mode': completionMode!.name,
        if (cactusToken != null) 'cactus_token': cactusToken,
      };
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

  double get tps => decodeTps;
  double get tokensPerSecond => decodeTps;
  List<FunctionCall>? get toolCalls => functionCalls;
}

class CactusStreamedCompletionResult {
  final Stream<String> stream;
  final Future<CactusLMCompleteResult> result;

  CactusStreamedCompletionResult({required this.stream, required this.result});
}

class CactusLMEmbedResult {
  final List<double> embedding;

  CactusLMEmbedResult({required this.embedding});

  List<double> get embeddings => embedding;
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

  RagQueryChunk(
      {required this.score, required this.source, required this.content});
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

  Map<String, dynamic> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (topK != null) 'top_k': topK,
        if (topP != null) 'top_p': topP,
        'max_tokens': maxTokens,
        'stop_sequences': stopSequences,
        if (useVad != null) 'use_vad': useVad,
        if (telemetryEnabled != null) 'telemetry_enabled': telemetryEnabled,
        if (confidenceThreshold != null)
          'confidence_threshold': confidenceThreshold,
        if (cloudHandoffThreshold != null)
          'cloud_handoff_threshold': cloudHandoffThreshold,
        if (includeStopSequences != null)
          'include_stop_sequences': includeStopSequences,
      };
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

  String get text => response;
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

  Map<String, dynamic> toJson() => {
        if (confirmationThreshold != null)
          'confirmation_threshold': confirmationThreshold,
        if (minChunkSize != null) 'min_chunk_size': minChunkSize,
        if (telemetryEnabled != null) 'telemetry_enabled': telemetryEnabled,
        if (language != null) 'language': language,
      };
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

  CactusSTTStreamTranscribeStopResult(
      {required this.success, required this.confirmed});
}

class CactusSTTDetectLanguageResult {
  final String language;
  final double? confidence;

  CactusSTTDetectLanguageResult({required this.language, this.confidence});
}

class CactusSTTDetectLanguageOptions {
  final bool? useVad;

  const CactusSTTDetectLanguageOptions({this.useVad});

  Map<String, dynamic> toJson() => {
        if (useVad != null) 'use_vad': useVad,
      };
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

  Map<String, dynamic> toJson() => {
        if (threshold != null) 'threshold': threshold,
        if (negThreshold != null) 'neg_threshold': negThreshold,
        if (minSpeechDurationMs != null)
          'min_speech_duration_ms': minSpeechDurationMs,
        if (maxSpeechDurationS != null)
          'max_speech_duration_s': maxSpeechDurationS,
        if (minSilenceDurationMs != null)
          'min_silence_duration_ms': minSilenceDurationMs,
        if (speechPadMs != null) 'speech_pad_ms': speechPadMs,
        if (windowSizeSamples != null) 'window_size_samples': windowSizeSamples,
        if (samplingRate != null) 'sampling_rate': samplingRate,
        if (minSilenceAtMaxSpeech != null)
          'min_silence_at_max_speech': minSilenceAtMaxSpeech,
        if (useMaxPossSilAtMaxSpeech != null)
          'use_max_poss_sil_at_max_speech': useMaxPossSilAtMaxSpeech,
      };
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

  CactusAudioVADResult(
      {this.segments = const [],
      required this.totalTime,
      required this.ramUsage});
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

  Map<String, dynamic> toJson() => {
        if (stepMs != null) 'step_ms': stepMs,
        if (threshold != null) 'threshold': threshold,
        if (numSpeakers != null) 'num_speakers': numSpeakers,
        if (minSpeakers != null) 'min_speakers': minSpeakers,
        if (maxSpeakers != null) 'max_speakers': maxSpeakers,
      };
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

  Map<String, dynamic> toJson() => {
        if (stepMs != null) 'step_ms': stepMs,
        if (threshold != null) 'threshold': threshold,
        if (maskWeights != null) 'mask_weights': maskWeights,
        if (maskNumFrames != null) 'mask_num_frames': maskNumFrames,
      };
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

  Map<String, dynamic> toJson() => {
        if (topK != null) 'top_k': topK,
        if (scoreThreshold != null) 'score_threshold': scoreThreshold,
      };
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

class ChunkSearchResult {
  final String text;
  final double score;
  final Map<String, dynamic>? metadata;

  ChunkSearchResult({required this.text, required this.score, this.metadata});

  String get chunk => text;
}

class DatabaseStats {
  final int count;
  final int dimension;

  DatabaseStats({required this.count, required this.dimension});

  int get totalDocuments => count;
}

typedef VoiceModel = CactusModel;

class CactusTranscriptionResult {
  final String text;
  final bool isFinal;

  CactusTranscriptionResult({required this.text, required this.isFinal});

  // For compatibility with stream-based transcribeStream
  Stream<CactusTranscriptionResult> get stream => Stream.value(this);
  Future<CactusTranscriptionResult> get result => Future.value(this);
  double get timeToFirstTokenMs => 0.0;
  double get totalTimeMs => 0.0;
}
