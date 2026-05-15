import 'dart:async';

import 'package:cactus/models/tools.dart';

/// Defines the execution mode for a completion request.
///
/// [local] runs inference entirely on-device. [cloud] runs inference on
/// Cactus servers. [hybrid] attempts local first and falls back to cloud.
enum CompletionMode { local, cloud, hybrid }

/// The role of a message sender in a conversation.
enum CactusLMRole { system, user, assistant, tool }

/// Callback invoked for each token as it is generated during streaming.
typedef CactusTokenCallback = void Function(String token);

/// Callback invoked to report progress of an ongoing operation.
///
/// [progress]: A value between 0.0 and 1.0, or null if indeterminate.
/// [statusMessage]: A human-readable description of the current step.
/// [isError]: Whether [statusMessage] describes an error condition.
typedef CactusProgressCallback = void Function(
    double? progress, String statusMessage, bool isError);

/// Alias for [CactusLMMessage].
typedef ChatMessage = CactusLMMessage;

/// Alias for [CactusLMCompleteOptions].
typedef CactusCompletionParams = CactusLMCompleteOptions;

/// Alias for [CactusLMCompleteResult].
typedef CactusCompletionResult = CactusLMCompleteResult;

/// Alias for [CactusLMCompleteOptions].
typedef CactusInitParams = CactusLMCompleteOptions;

/// Alias for [CactusTool] for backwards compatibility.
typedef CactusLMTool = CactusTool;

/// Configuration for loading a Cactus model.
class CactusModelOptions {
  /// The quantization format to use (e.g. `'int8'`, `'int4'`).
  final String quantization;

  /// Whether to enable Pro (cloud-assisted) features.
  final bool pro;

  /// Creates [CactusModelOptions] with optional overrides.
  ///
  /// [quantization]: The quantization format (default `'int8'`).
  /// [pro]: Whether to enable Pro features (default `false`).
  const CactusModelOptions({
    this.quantization = 'int8',
    this.pro = false,
  });
}

/// A message in a multi-turn conversation with a language model.
class CactusLMMessage {
  /// The role of the message sender.
  final CactusLMRole role;

  /// The text content of the message, or null for tool calls.
  final String? content;

  /// Base64-encoded images attached to the message.
  final List<String> images;

  /// Audio file paths attached to the message (for multimodal models).
  final List<String> audio;

  /// Creates a [CactusLMMessage].
  ///
  /// [role]: The sender role.
  /// [content]: The text content (optional).
  /// [images]: Base64 image strings (default empty).
  /// [audio]: Audio file paths (default empty).
  CactusLMMessage({
    required this.role,
    this.content,
    this.images = const [],
    this.audio = const [],
  });

  /// Creates a [CactusLMMessage] with a string role for convenience.
  factory CactusLMMessage.fromRoleString(
    String role, {
    String? content,
    List<String>? images,
    List<String>? audio,
  }) {
    return CactusLMMessage(
      role: CactusLMRole.values.firstWhere(
        (r) => r.name == role,
        orElse: () => CactusLMRole.user,
      ),
      content: content,
      images: images ?? const [],
      audio: audio ?? const [],
    );
  }

  /// Serializes this message to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'role': role.name,
        if (content != null) 'content': content,
        if (images.isNotEmpty) 'images': images,
        if (audio.isNotEmpty) 'audio': audio,
      };
}

/// Represents a function call returned by the model.
class FunctionCall {
  /// The name of the function to invoke.
  final String name;

  /// The arguments to pass to the function, as a JSON-compatible map.
  final Map<String, dynamic> arguments;

  /// Creates a [FunctionCall].
  ///
  /// [name]: The function name.
  /// [arguments]: The function arguments.
  FunctionCall({required this.name, required this.arguments});
}

/// Options for a language model completion request.
class CactusLMCompleteOptions {
  /// Sampling temperature (higher values produce more random output).
  final double? temperature;

  /// Top-k sampling: only consider the [topK] most likely tokens.
  final int? topK;

  /// Nucleus sampling probability threshold.
  final double? topP;

  /// Minimum probability threshold relative to the highest probability token.
  final double? minP;

  /// Penalizes repeated tokens (1.0 disables).
  final double? repetitionPenalty;

  /// Maximum number of tokens to generate.
  final int maxTokens;

  /// Sequences at which generation will stop.
  final List<String> stopSequences;

  /// If true, forces the model to always invoke a tool.
  final bool? forceTools;

  /// Whether telemetry data may be collected.
  final bool? telemetryEnabled;

  /// Minimum confidence threshold for cloud fallback.
  final double? confidenceThreshold;

  /// Whether stop sequences should be included in the output.
  final bool? includeStopSequences;

  /// If true, enables the model's extended reasoning / thinking mode.
  final bool? enableThinking;

  /// Select top-k relevant tools via Tool RAG (0 = disabled, use all tools).
  final int? toolRagTopK;

  /// Automatically attempt cloud handoff when confidence is low.
  final bool? autoHandoff;

  /// Timeout in milliseconds for cloud handoff requests.
  final int? cloudTimeoutMs;

  /// Allow cloud handoff for requests that include images.
  final bool? handoffWithImages;

  /// Overrides the default completion mode for this request.
  final CompletionMode? completionMode;

  /// An optional authentication token for cloud services.
  final String? cactusToken;

  /// Creates [CactusLMCompleteOptions] with optional overrides.
  ///
  /// [temperature]: Sampling temperature (default null).
  /// [topK]: Top-k sampling limit (default null).
  /// [topP]: Nucleus sampling threshold (default null).
  /// [minP]: Minimum probability threshold (default null).
  /// [repetitionPenalty]: Token repetition penalty (default null).
  /// [maxTokens]: Maximum output tokens (default 512).
  /// [stopSequences]: Stop sequences (default `['<|im_end|>', '<end_of_turn>']`).
  /// [forceTools]: Force tool invocation (default null).
  /// [telemetryEnabled]: Telemetry opt-in (default null).
  /// [confidenceThreshold]: Cloud fallback threshold (default null).
  /// [includeStopSequences]: Include stop sequences in output (default null).
  /// [enableThinking]: Enable thinking mode (default null).
  /// [toolRagTopK]: Tool RAG top-k (default null).
  /// [autoHandoff]: Auto cloud handoff (default null).
  /// [cloudTimeoutMs]: Cloud timeout in ms (default null).
  /// [handoffWithImages]: Cloud handoff with images (default null).
  /// [completionMode]: Request-level mode override (default null).
  /// [cactusToken]: Cloud auth token (default null).
  const CactusLMCompleteOptions({
    this.temperature,
    this.topK,
    this.topP,
    this.minP,
    this.repetitionPenalty,
    this.maxTokens = 512,
    this.stopSequences = const ['<|im_end|>', '<end_of_turn>'],
    this.forceTools,
    this.telemetryEnabled,
    this.confidenceThreshold,
    this.includeStopSequences,
    this.enableThinking,
    this.toolRagTopK,
    this.autoHandoff,
    this.cloudTimeoutMs,
    this.handoffWithImages,
    this.completionMode,
    this.cactusToken,
  });

  /// Serializes these options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (topK != null) 'top_k': topK,
        if (topP != null) 'top_p': topP,
        if (minP != null) 'min_p': minP,
        if (repetitionPenalty != null)
          'repetition_penalty': repetitionPenalty,
        'max_tokens': maxTokens,
        'stop_sequences': stopSequences,
        if (forceTools != null) 'force_tools': forceTools,
        if (telemetryEnabled != null) 'telemetry_enabled': telemetryEnabled,
        if (confidenceThreshold != null)
          'confidence_threshold': confidenceThreshold,
        if (includeStopSequences != null)
          'include_stop_sequences': includeStopSequences,
        if (enableThinking != null)
          'enable_thinking_if_supported': enableThinking,
        if (toolRagTopK != null) 'tool_rag_top_k': toolRagTopK,
        if (autoHandoff != null) 'auto_handoff': autoHandoff,
        if (cloudTimeoutMs != null) 'cloud_timeout_ms': cloudTimeoutMs,
        if (handoffWithImages != null) 'handoff_with_images': handoffWithImages,
        if (completionMode != null) 'completion_mode': completionMode!.name,
        if (cactusToken != null) 'cactus_token': cactusToken,
      };
}

/// The result of a language model completion.
class CactusLMCompleteResult {
  /// Whether the completion succeeded.
  final bool success;

  /// The generated text response.
  final String response;

  /// The model's reasoning or thinking trace, if available.
  final String? thinking;

  /// Any function calls the model requested.
  final List<FunctionCall>? functionCalls;

  /// Whether the request was handled by the cloud.
  final bool? cloudHandoff;

  /// The model's confidence in the response (0.0 – 1.0).
  final double? confidence;

  /// Milliseconds until the first output token was produced.
  final double timeToFirstTokenMs;

  /// Total processing time in milliseconds.
  final double totalTimeMs;

  /// Number of tokens processed during the prefill phase.
  final int prefillTokens;

  /// Tokens per second during the prefill phase.
  final double prefillTps;

  /// Number of tokens generated during the decode phase.
  final int decodeTokens;

  /// Tokens per second during the decode phase.
  final double decodeTps;

  /// Total tokens processed (prefill + decode).
  final int totalTokens;

  /// Peak RAM usage in MB, if available.
  final double? ramUsageMb;

  /// Creates a [CactusLMCompleteResult].
  ///
  /// [success]: Whether the call succeeded.
  /// [response]: The generated text.
  /// [thinking]: Optional reasoning trace.
  /// [functionCalls]: Optional function calls.
  /// [cloudHandoff]: Whether cloud was used.
  /// [confidence]: Model confidence score.
  /// [timeToFirstTokenMs]: Time to first token.
  /// [totalTimeMs]: Total processing time.
  /// [prefillTokens]: Prefill token count.
  /// [prefillTps]: Prefill throughput.
  /// [decodeTokens]: Decode token count.
  /// [decodeTps]: Decode throughput.
  /// [totalTokens]: Total token count.
  /// [ramUsageMb]: Peak RAM usage.
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

  /// The decode throughput in tokens per second.
  double get tps => decodeTps;

  /// Alias for [tps].
  double get tokensPerSecond => decodeTps;

  /// Alias for [functionCalls].
  List<FunctionCall>? get toolCalls => functionCalls;
}

/// A streaming completion that yields tokens as they are generated.
class CactusStreamedCompletionResult {
  /// A stream of partial response tokens.
  final Stream<String> stream;

  /// A future that completes with the full result when generation finishes.
  final Future<CactusLMCompleteResult> result;

  /// Creates a [CactusStreamedCompletionResult].
  ///
  /// [stream]: The token stream.
  /// [result]: Future for the final result.
  CactusStreamedCompletionResult({required this.stream, required this.result});
}

/// The result of an embedding request for text.
class CactusLMEmbedResult {
  /// The embedding vector.
  final List<double> embedding;

  /// Creates a [CactusLMEmbedResult].
  ///
  /// [embedding]: The embedding vector.
  CactusLMEmbedResult({required this.embedding});

  /// Alias for [embedding].
  List<double> get embeddings => embedding;
}

/// The result of an embedding request for images.
class CactusLMImageEmbedResult {
  /// The embedding vector.
  final List<double> embedding;

  /// Creates a [CactusLMImageEmbedResult].
  ///
  /// [embedding]: The embedding vector.
  CactusLMImageEmbedResult({required this.embedding});
}

/// The result of pre-filling a model's prompt cache.
class CactusLMPrefillResult {
  /// Whether prefill succeeded.
  final bool success;

  /// An error message if prefill failed.
  final String? error;

  /// Number of tokens prefilled.
  final int prefillTokens;

  /// Tokens per second during prefill.
  final double prefillTps;

  /// Total prefill time in milliseconds.
  final double totalTimeMs;

  /// RAM usage in MB during prefill.
  final double ramUsageMb;

  /// Creates a [CactusLMPrefillResult].
  ///
  /// [success]: Whether prefill succeeded.
  /// [error]: Optional error message.
  /// [prefillTokens]: Tokens prefilled (default 0).
  /// [prefillTps]: Prefill throughput (default 0).
  /// [totalTimeMs]: Total time (default 0).
  /// [ramUsageMb]: RAM usage (default 0).
  CactusLMPrefillResult({
    required this.success,
    this.error,
    this.prefillTokens = 0,
    this.prefillTps = 0.0,
    this.totalTimeMs = 0.0,
    this.ramUsageMb = 0.0,
  });
}

/// The result of tokenizing a text string.
class CactusLMTokenizeResult {
  /// The token IDs.
  final List<int> tokens;

  /// Creates a [CactusLMTokenizeResult].
  ///
  /// [tokens]: The token IDs.
  CactusLMTokenizeResult({required this.tokens});
}

/// The result of scoring a text window.
class CactusLMScoreWindowResult {
  /// The log-probability of the scored token window.
  final double score;

  /// Number of tokens scored in the window.
  final int tokens;

  /// Creates a [CactusLMScoreWindowResult].
  ///
  /// [score]: The window log-probability.
  /// [tokens]: Number of tokens scored.
  CactusLMScoreWindowResult({required this.score, this.tokens = 0});
}

/// A single chunk returned from a RAG (retrieval-augmented generation) query.
class RagQueryChunk {
  /// The relevance score of this chunk.
  final double score;

  /// The source identifier of the chunk.
  final String source;

  /// The text content of the chunk.
  final String content;

  /// Creates a [RagQueryChunk].
  ///
  /// [score]: The relevance score.
  /// [source]: The source identifier.
  /// [content]: The chunk text.
  RagQueryChunk(
      {required this.score, required this.source, required this.content});
}

/// The result of a RAG (retrieval-augmented generation) query.
class CactusLMRagQueryResult {
  /// The ordered list of relevant chunks.
  final List<RagQueryChunk> chunks;

  /// An error message if the query failed.
  final String? error;

  /// Creates a [CactusLMRagQueryResult].
  ///
  /// [chunks]: Relevant chunks (default empty).
  /// [error]: Optional error message.
  CactusLMRagQueryResult({this.chunks = const [], this.error});
}

/// Options for transcribing audio with a speech-to-text model.
class CactusSTTTranscribeOptions {
  /// Sampling temperature.
  final double? temperature;

  /// Top-k sampling limit.
  final int? topK;

  /// Nucleus sampling threshold.
  final double? topP;

  /// Maximum number of tokens to generate.
  final int maxTokens;

  /// Sequences that stop generation.
  final List<String> stopSequences;

  /// Whether to apply voice activity detection before transcription.
  final bool? useVad;

  /// Whether telemetry data may be collected.
  final bool? telemetryEnabled;

  /// Minimum confidence threshold for the transcription.
  final double? confidenceThreshold;

  /// Confidence below which the request is handed off to the cloud.
  final double? cloudHandoffThreshold;

  /// Whether stop sequences should be included in the output.
  final bool? includeStopSequences;

  /// Words or phrases to boost recognition probability.
  final List<String>? customVocabulary;

  /// Log-probability bias for [customVocabulary] tokens (0.0–20.0).
  final double? vocabularyBoost;

  /// Creates [CactusSTTTranscribeOptions] with optional overrides.
  ///
  /// [temperature]: Sampling temperature (default null).
  /// [topK]: Top-k limit (default null).
  /// [topP]: Nucleus threshold (default null).
  /// [maxTokens]: Max output tokens (default 384).
  /// [stopSequences]: Stop sequences (default `['<|startoftranscript|>']`).
  /// [useVad]: Enable VAD (default null).
  /// [telemetryEnabled]: Telemetry opt-in (default null).
  /// [confidenceThreshold]: Confidence floor (default null).
  /// [cloudHandoffThreshold]: Cloud handoff threshold (default null).
  /// [includeStopSequences]: Include stop sequences (default null).
  /// [customVocabulary]: Custom vocabulary list (default null).
  /// [vocabularyBoost]: Vocabulary boost strength (default null).
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
    this.customVocabulary,
    this.vocabularyBoost,
  });

  /// Serializes these options to a JSON-compatible map.
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
        if (customVocabulary != null) 'custom_vocabulary': customVocabulary,
        if (vocabularyBoost != null) 'vocabulary_boost': vocabularyBoost,
      };
}

/// The result of a speech-to-text transcription.
class CactusSTTTranscribeResult {
  /// Whether transcription succeeded.
  final bool success;

  /// The transcribed text.
  final String response;

  /// Whether the request was handled by the cloud.
  final bool? cloudHandoff;

  /// The model's confidence in the transcription.
  final double? confidence;

  /// Milliseconds until the first token was produced.
  final double timeToFirstTokenMs;

  /// Total processing time in milliseconds.
  final double totalTimeMs;

  /// Number of tokens processed during prefill.
  final int prefillTokens;

  /// Tokens per second during prefill.
  final double prefillTps;

  /// Number of tokens generated during decode.
  final int decodeTokens;

  /// Tokens per second during decode.
  final double decodeTps;

  /// Total tokens processed.
  final int totalTokens;

  /// Peak RAM usage in MB, if available.
  final double? ramUsageMb;

  /// Creates a [CactusSTTTranscribeResult].
  ///
  /// [success]: Whether transcription succeeded.
  /// [response]: The transcribed text.
  /// [cloudHandoff]: Whether cloud was used.
  /// [confidence]: Confidence score.
  /// [timeToFirstTokenMs]: Time to first token.
  /// [totalTimeMs]: Total processing time.
  /// [prefillTokens]: Prefill token count.
  /// [prefillTps]: Prefill throughput.
  /// [decodeTokens]: Decode token count.
  /// [decodeTps]: Decode throughput.
  /// [totalTokens]: Total token count.
  /// [ramUsageMb]: Peak RAM usage.
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

  /// Alias for [response].
  String get text => response;
}

/// The result of embedding audio.
class CactusSTTAudioEmbedResult {
  /// The embedding vector.
  final List<double> embedding;

  /// Creates a [CactusSTTAudioEmbedResult].
  ///
  /// [embedding]: The embedding vector.
  CactusSTTAudioEmbedResult({required this.embedding});
}

/// Options for starting a streaming speech-to-text transcription session.
class CactusSTTStreamTranscribeStartOptions {
  /// Confidence threshold for confirming a segment.
  final double? confirmationThreshold;

  /// Minimum chunk size for streaming transcription.
  final int? minChunkSize;

  /// Whether telemetry data may be collected.
  final bool? telemetryEnabled;

  /// The expected language of the audio.
  final String? language;

  /// Words or phrases to boost recognition probability.
  final List<String>? customVocabulary;

  /// Log-probability bias for [customVocabulary] tokens (0.0–20.0).
  final double? vocabularyBoost;

  /// Creates [CactusSTTStreamTranscribeStartOptions] with optional overrides.
  ///
  /// [confirmationThreshold]: Confidence threshold (default null).
  /// [minChunkSize]: Minimum chunk size (default null).
  /// [telemetryEnabled]: Telemetry opt-in (default null).
  /// [language]: Expected language (default null).
  /// [customVocabulary]: Custom vocabulary list (default null).
  /// [vocabularyBoost]: Vocabulary boost strength (default null).
  const CactusSTTStreamTranscribeStartOptions({
    this.confirmationThreshold,
    this.minChunkSize,
    this.telemetryEnabled,
    this.language,
    this.customVocabulary,
    this.vocabularyBoost,
  });

  /// Serializes these options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        if (confirmationThreshold != null)
          'confirmation_threshold': confirmationThreshold,
        if (minChunkSize != null) 'min_chunk_size': minChunkSize,
        if (telemetryEnabled != null) 'telemetry_enabled': telemetryEnabled,
        if (language != null) 'language': language,
        if (customVocabulary != null) 'custom_vocabulary': customVocabulary,
        if (vocabularyBoost != null) 'vocabulary_boost': vocabularyBoost,
      };
}

/// An intermediate result from a streaming transcription session.
class CactusSTTStreamTranscribeProcessResult {
  /// Whether the audio chunk was processed successfully.
  final bool success;

  /// The fully confirmed transcription text so far.
  final String confirmed;

  /// The pending (unconfirmed) transcription text.
  final String pending;

  /// Duration of the audio buffer processed, in milliseconds.
  final double? bufferDurationMs;

  /// Error message if processing failed.
  final String? error;

  /// Whether the chunk was handed off to cloud.
  final bool? cloudHandoff;

  /// ID of the cloud job queued in this call (0 if none).
  final int cloudJobId;

  /// ID of the cloud job whose result is returned (0 if none ready).
  final int cloudResultJobId;

  /// Transcript returned by the completed cloud job.
  final String? cloudResult;

  /// Whether the completed cloud job reached a cloud API.
  final bool? cloudResultUsedCloud;

  /// Error message from the cloud job.
  final String? cloudResultError;

  /// Source of cloud result: "cloud" or "fallback".
  final String? cloudResultSource;

  /// The confirmed text as produced by the local model.
  final String? confirmedLocal;

  /// Timestamped transcription segments.
  final List<CactusSTTStreamSegment> segments;

  /// Function calls generated in this chunk.
  final List<FunctionCall>? functionCalls;

  /// Confidence of the current transcription.
  final double? confidence;

  /// Milliseconds until the first token for this chunk.
  final double? timeToFirstTokenMs;

  /// Total processing time for this chunk.
  final double? totalTimeMs;

  /// Prefill token count for this chunk.
  final int? prefillTokens;

  /// Prefill throughput for this chunk.
  final double? prefillTps;

  /// Decode token count for this chunk.
  final int? decodeTokens;

  /// Decode throughput for this chunk.
  final double? decodeTps;

  /// Total tokens for this chunk.
  final int? totalTokens;

  /// Peak RAM usage in MB.
  final double? ramUsageMb;

  /// Creates a [CactusSTTStreamTranscribeProcessResult].
  ///
  /// [success]: Whether the processing call succeeded.
  /// [confirmed]: Fully confirmed transcription text so far.
  /// [pending]: Uncommitted (in-progress) transcription text.
  /// [bufferDurationMs]: Duration of audio processed in this chunk.
  /// [error]: Error message if the call failed.
  /// [cloudHandoff]: Whether cloud handoff was triggered.
  /// [cloudJobId]: Cloud job identifier.
  /// [cloudResultJobId]: Cloud result job identifier.
  /// [cloudResult]: Cloud transcription result text.
  /// [cloudResultUsedCloud]: Whether the cloud result was used.
  /// [cloudResultError]: Cloud result error message.
  /// [cloudResultSource]: Source identifier for the cloud result.
  /// [confirmedLocal]: Locally confirmed text (before cloud handoff).
  /// [segments]: Timestamped transcription segments.
  /// [functionCalls]: Function calls detected in the transcription.
  /// [confidence]: Confidence score for this chunk.
  /// [timeToFirstTokenMs]: Milliseconds until the first token.
  /// [totalTimeMs]: Total processing time for this chunk.
  /// [prefillTokens]: Prefill token count.
  /// [prefillTps]: Prefill throughput.
  /// [decodeTokens]: Decode token count.
  /// [decodeTps]: Decode throughput.
  /// [totalTokens]: Total tokens processed.
  /// [ramUsageMb]: Peak RAM usage in MB.
  CactusSTTStreamTranscribeProcessResult({
    required this.success,
    required this.confirmed,
    required this.pending,
    this.bufferDurationMs,
    this.error,
    this.cloudHandoff,
    this.cloudJobId = 0,
    this.cloudResultJobId = 0,
    this.cloudResult,
    this.cloudResultUsedCloud,
    this.cloudResultError,
    this.cloudResultSource,
    this.confirmedLocal,
    this.segments = const [],
    this.functionCalls,
    this.confidence,
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

/// A single transcription segment with timestamps from a streaming
/// transcription session.
class CactusSTTStreamSegment {
  /// Start time in seconds relative to the beginning of the stream.
  final double start;

  /// End time in seconds relative to the beginning of the stream.
  final double end;

  /// The transcribed text for this segment.
  final String text;

  /// Creates a [CactusSTTStreamSegment].
  ///
  /// [start]: Start time in seconds.
  /// [end]: End time in seconds.
  /// [text]: The transcribed text for this segment.
  const CactusSTTStreamSegment({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// The final result returned when a streaming transcription session is stopped.
class CactusSTTStreamTranscribeStopResult {
  /// Whether the session was stopped cleanly.
  final bool success;

  /// The fully confirmed transcription text.
  final String confirmed;

  /// Creates a [CactusSTTStreamTranscribeStopResult].
  ///
  /// [success]: Whether the stop was successful.
  /// [confirmed]: The final transcription text.
  CactusSTTStreamTranscribeStopResult(
      {required this.success, required this.confirmed});
}

/// The result of detecting the language of an audio segment.
class CactusSTTDetectLanguageResult {
  /// The detected language code (e.g. `'en'`, `'fr'`).
  final String language;

  /// The model's confidence in the detected language.
  final double? confidence;

  /// Creates a [CactusSTTDetectLanguageResult].
  ///
  /// [language]: The detected language code.
  /// [confidence]: Confidence score (optional).
  CactusSTTDetectLanguageResult({required this.language, this.confidence});
}

/// Options for language detection in audio.
class CactusSTTDetectLanguageOptions {
  /// Whether to apply voice activity detection before language detection.
  final bool? useVad;

  /// Creates [CactusSTTDetectLanguageOptions] with optional overrides.
  ///
  /// [useVad]: Enable VAD (default null).
  const CactusSTTDetectLanguageOptions({this.useVad});

  /// Serializes these options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        if (useVad != null) 'use_vad': useVad,
      };
}

/// Options for voice activity detection (VAD).
class CactusAudioVADOptions {
  /// The VAD activation threshold.
  final double? threshold;

  /// The deactivation threshold for ending speech.
  final double? negThreshold;

  /// Minimum speech duration in milliseconds.
  final int? minSpeechDurationMs;

  /// Maximum speech duration in seconds.
  final double? maxSpeechDurationS;

  /// Minimum silence duration in milliseconds.
  final int? minSilenceDurationMs;

  /// Padding in milliseconds added around speech segments.
  final int? speechPadMs;

  /// Window size in samples for VAD processing.
  final int? windowSizeSamples;

  /// Audio sampling rate in Hz.
  final int? samplingRate;

  /// Minimum silence required when max speech duration is reached.
  final int? minSilenceAtMaxSpeech;

  /// Whether to use maximum possible silence at max speech duration.
  final bool? useMaxPossSilAtMaxSpeech;

  /// Creates [CactusAudioVADOptions] with optional overrides.
  ///
  /// [threshold]: Activation threshold (default null).
  /// [negThreshold]: Deactivation threshold (default null).
  /// [minSpeechDurationMs]: Min speech duration (default null).
  /// [maxSpeechDurationS]: Max speech duration (default null).
  /// [minSilenceDurationMs]: Min silence duration (default null).
  /// [speechPadMs]: Speech padding (default null).
  /// [windowSizeSamples]: Window size in samples (default null).
  /// [samplingRate]: Sampling rate (default null).
  /// [minSilenceAtMaxSpeech]: Min silence at max speech (default null).
  /// [useMaxPossSilAtMaxSpeech]: Use max possible silence flag (default null).
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

  /// Serializes these options to a JSON-compatible map.
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

/// A single speech segment detected by VAD.
class CactusAudioVADSegment {
  /// Start sample index of the segment.
  final int start;

  /// End sample index of the segment.
  final int end;

  /// Creates a [CactusAudioVADSegment].
  ///
  /// [start]: Start sample index.
  /// [end]: End sample index.
  CactusAudioVADSegment({required this.start, required this.end});
}

/// The result of voice activity detection on an audio buffer.
class CactusAudioVADResult {
  /// The detected speech segments.
  final List<CactusAudioVADSegment> segments;

  /// Total audio duration processed in seconds.
  final double totalTime;

  /// RAM usage during VAD processing.
  final double ramUsage;

  /// Creates a [CactusAudioVADResult].
  ///
  /// [segments]: Detected speech segments (default empty).
  /// [totalTime]: Total audio duration in seconds.
  /// [ramUsage]: RAM usage.
  CactusAudioVADResult(
      {this.segments = const [],
      required this.totalTime,
      required this.ramUsage});
}

/// Options for speaker diarization (identifying who spoke when).
class CactusAudioDiarizeOptions {
  /// Step size in milliseconds for the diarization window.
  final int? stepMs;

  /// Similarity threshold for assigning a segment to a speaker.
  final double? threshold;

  /// Exact number of speakers to detect.
  final int? numSpeakers;

  /// Minimum number of speakers.
  final int? minSpeakers;

  /// Maximum number of speakers.
  final int? maxSpeakers;

  /// Creates [CactusAudioDiarizeOptions] with optional overrides.
  ///
  /// [stepMs]: Window step in ms (default null).
  /// [threshold]: Similarity threshold (default null).
  /// [numSpeakers]: Exact speaker count (default null).
  /// [minSpeakers]: Minimum speakers (default null).
  /// [maxSpeakers]: Maximum speakers (default null).
  const CactusAudioDiarizeOptions({
    this.stepMs,
    this.threshold,
    this.numSpeakers,
    this.minSpeakers,
    this.maxSpeakers,
  });

  /// Serializes these options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        if (stepMs != null) 'step_ms': stepMs,
        if (threshold != null) 'threshold': threshold,
        if (numSpeakers != null) 'num_speakers': numSpeakers,
        if (minSpeakers != null) 'min_speakers': minSpeakers,
        if (maxSpeakers != null) 'max_speakers': maxSpeakers,
      };
}

/// The result of speaker diarization.
class CactusAudioDiarizeResult {
  /// Whether diarization succeeded.
  final bool success;

  /// An error message if diarization failed.
  final String? error;

  /// The number of unique speakers detected.
  final int numSpeakers;

  /// Confidence scores for each detected speaker.
  final List<double> scores;

  /// Total processing time in milliseconds.
  final double totalTimeMs;

  /// Peak RAM usage in MB.
  final double ramUsageMb;

  /// Creates a [CactusAudioDiarizeResult].
  ///
  /// [success]: Whether diarization succeeded.
  /// [error]: Optional error message.
  /// [numSpeakers]: Detected speaker count (default 0).
  /// [scores]: Per-speaker confidence scores (default empty).
  /// [totalTimeMs]: Total processing time (default 0).
  /// [ramUsageMb]: Peak RAM usage (default 0).
  CactusAudioDiarizeResult({
    required this.success,
    this.error,
    this.numSpeakers = 0,
    this.scores = const [],
    this.totalTimeMs = 0.0,
    this.ramUsageMb = 0.0,
  });
}

/// Options for generating speaker embeddings from audio.
class CactusAudioEmbedSpeakerOptions {
  /// Step size in milliseconds for the embedding window.
  final int? stepMs;

  /// Similarity threshold for speaker matching.
  final double? threshold;

  /// Optional weights to apply to the embedding mask.
  final List<double>? maskWeights;

  /// Number of frames to use for the embedding mask.
  final int? maskNumFrames;

  /// Creates [CactusAudioEmbedSpeakerOptions] with optional overrides.
  ///
  /// [stepMs]: Window step in ms (default null).
  /// [threshold]: Similarity threshold (default null).
  /// [maskWeights]: Mask weights (default null).
  /// [maskNumFrames]: Mask frame count (default null).
  const CactusAudioEmbedSpeakerOptions({
    this.stepMs,
    this.threshold,
    this.maskWeights,
    this.maskNumFrames,
  });

  /// Serializes these options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        if (stepMs != null) 'step_ms': stepMs,
        if (threshold != null) 'threshold': threshold,
        if (maskWeights != null) 'mask_weights': maskWeights,
        if (maskNumFrames != null) 'mask_num_frames': maskNumFrames,
      };
}

/// The result of generating a speaker embedding.
class CactusAudioEmbedSpeakerResult {
  /// Whether embedding succeeded.
  final bool success;

  /// An error message if embedding failed.
  final String? error;

  /// The speaker embedding vector.
  final List<double> embedding;

  /// Total processing time in milliseconds.
  final double totalTimeMs;

  /// Peak RAM usage in MB.
  final double ramUsageMb;

  /// Creates a [CactusAudioEmbedSpeakerResult].
  ///
  /// [success]: Whether embedding succeeded.
  /// [error]: Optional error message.
  /// [embedding]: The embedding vector (default empty).
  /// [totalTimeMs]: Total processing time (default 0).
  /// [ramUsageMb]: Peak RAM usage (default 0).
  CactusAudioEmbedSpeakerResult({
    required this.success,
    this.error,
    this.embedding = const [],
    this.totalTimeMs = 0.0,
    this.ramUsageMb = 0.0,
  });
}

/// The result of fetching documents and metadata from an index.
class CactusIndexGetResult {
  /// The list of document texts.
  final List<String> documents;

  /// The corresponding metadata entries.
  final List<String> metadatas;

  /// The corresponding embedding vectors.
  final List<List<double>> embeddings;

  /// Creates a [CactusIndexGetResult].
  ///
  /// [documents]: Document texts (default empty).
  /// [metadatas]: Document metadata (default empty).
  /// [embeddings]: Embedding vectors (default empty).
  CactusIndexGetResult({
    this.documents = const [],
    this.metadatas = const [],
    this.embeddings = const [],
  });
}

/// Options for querying a vector index.
class CactusIndexQueryOptions {
  /// Maximum number of results to return.
  final int? topK;

  /// Minimum similarity score threshold.
  final double? scoreThreshold;

  /// Creates [CactusIndexQueryOptions] with optional overrides.
  ///
  /// [topK]: Max results (default null).
  /// [scoreThreshold]: Score floor (default null).
  const CactusIndexQueryOptions({this.topK, this.scoreThreshold});

  /// Serializes these options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        if (topK != null) 'top_k': topK,
        if (scoreThreshold != null) 'score_threshold': scoreThreshold,
      };
}

/// The result of querying a vector index.
class CactusIndexQueryResult {
  /// List of result ID lists (one per query).
  final List<List<int>> ids;

  /// List of score lists corresponding to [ids].
  final List<List<double>> scores;

  /// Creates a [CactusIndexQueryResult].
  ///
  /// [ids]: Result IDs (default empty).
  /// [scores]: Result scores (default empty).
  CactusIndexQueryResult({this.ids = const [], this.scores = const []});
}

/// An exception originating from the Cactus SDK.
class CactusException implements Exception {
  /// A human-readable error message.
  final String message;

  /// The underlying error that caused this exception, if any.
  final dynamic underlyingError;

  /// Creates a [CactusException].
  ///
  /// [message]: The error message.
  /// [underlyingError]: The root cause (optional).
  CactusException(this.message, [this.underlyingError]);

  @override
  /// Returns a formatted string representation of this exception.
  ///
  /// Includes the underlying error when present.
  /// Returns: A human-readable error string.
  String toString() {
    if (underlyingError != null) {
      return 'CactusException: $message (Caused by: $underlyingError)';
    }
    return 'CactusException: $message';
  }
}

/// Thrown when a download is already in progress.
class AlreadyDownloadingException extends CactusException {
  AlreadyDownloadingException() : super('Already downloading');

  @override
  String toString() => 'AlreadyDownloadingException: $message';
}

/// Thrown when attempting to download a model that is already cached locally.
class ModelAlreadyDownloadedException extends CactusException {
  ModelAlreadyDownloadedException() : super('Model already downloaded');

  @override
  String toString() => 'ModelAlreadyDownloadedException: $message';
}

/// Thrown when an operation requires a model that hasn't been downloaded yet.
class ModelNotDownloadedException extends CactusException {
  ModelNotDownloadedException() : super('Model not downloaded. Call download() first.');

  @override
  String toString() => 'ModelNotDownloadedException: $message';
}

/// Thrown when an operation requires the model context but it is not loaded.
class ModelNotInitializedException extends CactusException {
  ModelNotInitializedException() : super('Model not initialized');

  @override
  String toString() => 'ModelNotInitializedException: $message';
}

/// Thrown when an generation request arrives while one is already in flight.
class AlreadyGeneratingException extends CactusException {
  AlreadyGeneratingException() : super('Already generating');

  @override
  String toString() => 'AlreadyGeneratingException: $message';
}

/// Thrown when the requested model is not found in the Hugging Face registry.
class ModelNotFoundException extends CactusException {
  ModelNotFoundException(super.message);

  @override
  String toString() => 'ModelNotFoundException: $message';
}

/// Thrown when the native Cactus context fails to initialize.
class ModelInitFailedException extends CactusException {
  ModelInitFailedException(super.message);

  @override
  String toString() => 'ModelInitFailedException: $message';
}

/// Thrown when a file:// path is used for download instead of a model name.
class InvalidModelPathException extends CactusException {
  InvalidModelPathException() : super('Cannot download file:// paths');

  @override
  String toString() => 'InvalidModelPathException: $message';
}

/// Thrown when a streaming operation is attempted without starting the stream.
class StreamNotStartedException extends CactusException {
  StreamNotStartedException()
      : super('Stream transcription not started. Call streamTranscribeStart() first.');

  @override
  String toString() => 'StreamNotStartedException: $message';
}

/// Information required for Cactus Pro (cloud) access.
class CactusProInfo {
  /// The Apple App Store receipt data for Pro authentication.
  final String apple;

  /// Creates a [CactusProInfo].
  ///
  /// [apple]: The Apple receipt data.
  CactusProInfo({required this.apple});

  /// Constructs a [CactusProInfo] from a JSON map.
  factory CactusProInfo.fromJson(Map<String, dynamic> json) {
    return CactusProInfo(apple: json['apple'] as String);
  }

  /// Serializes this info to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'apple': apple};
}

/// Describes a single quantization variant of a model.
class CactusQuantizationInfo {
  /// The model size in MB for this quantization.
  final int sizeMb;

  /// The download URL for this quantized model.
  final String url;

  /// Optional Pro-specific information for this quantization.
  final CactusProInfo? pro;

  /// Creates a [CactusQuantizationInfo].
  ///
  /// [sizeMb]: Model size in MB.
  /// [url]: Download URL.
  /// [pro]: Optional Pro info.
  CactusQuantizationInfo({
    required this.sizeMb,
    required this.url,
    this.pro,
  });

  /// Constructs a [CactusQuantizationInfo] from a JSON map.
  factory CactusQuantizationInfo.fromJson(Map<String, dynamic> json) {
    return CactusQuantizationInfo(
      sizeMb: json['size_mb'] as int,
      url: json['url'] as String,
      pro: json['pro'] != null
          ? CactusProInfo.fromJson(json['pro'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Serializes this info to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'size_mb': sizeMb,
        'url': url,
        if (pro != null) 'pro': pro!.toJson(),
      };
}

/// A downloadable model with its metadata, capabilities, and quantization
/// variants.
class CactusModel {
  /// A unique identifier string for the model (e.g. `'llama-3-8b'`).
  final String slug;

  /// A human-readable display name.
  final String name;

  /// The list of capabilities the model supports (e.g. `'tools'`, `'vision'`).
  final List<String> capabilities;

  /// A map from quantization key (e.g. `'int4'`, `'int8'`) to its info.
  final Map<String, CactusQuantizationInfo> quantization;

  /// Whether this model has been downloaded locally.
  bool isDownloaded;

  DateTime? _createdAt;

  /// Creates a [CactusModel].
  ///
  /// [slug]: Unique model identifier.
  /// [name]: Display name.
  /// [capabilities]: Supported capabilities.
  /// [quantization]: Quantization variants.
  /// [isDownloaded]: Whether downloaded (default `false`).
  /// [createdAt]: Creation timestamp (optional).
  CactusModel({
    required this.slug,
    required this.name,
    required this.capabilities,
    required this.quantization,
    this.isDownloaded = false,
    DateTime? createdAt,
  }) : _createdAt = createdAt;

  /// The download URL for the int4 quantization variant, or empty.
  String get downloadUrl => quantization['int4']?.url ?? '';

  /// Whether this model supports tool / function calling.
  bool get supportsToolCalling => capabilities.contains('tools');

  /// Whether this model supports vision / image inputs.
  bool get supportsVision => capabilities.contains('vision');

  /// Whether this model supports thinking / reasoning.
  bool get supportsThinking => capabilities.contains('thinking');

  /// The size in MB of the int4 quantization variant, or 0.
  int get sizeMb => quantization['int4']?.sizeMb ?? 0;

  /// The creation date of this model, defaulting to year 2000 if unknown.
  DateTime get createdAt => _createdAt ?? DateTime(2000);

  /// Constructs a [CactusModel] from a JSON map.
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

  /// Serializes this model to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        'capabilities': capabilities,
        'quantization': quantization.map((k, v) => MapEntry(k, v.toJson())),
        'is_downloaded': isDownloaded,
        if (_createdAt != null) 'created_at': _createdAt!.toIso8601String(),
      };
}

/// A single chunk returned by a chunk-based search.
class ChunkSearchResult {
  /// The text content of the chunk.
  final String text;

  /// The relevance score of this chunk.
  final double score;

  /// Optional metadata associated with the chunk.
  final Map<String, dynamic>? metadata;

  /// Creates a [ChunkSearchResult].
  ///
  /// [text]: The chunk text.
  /// [score]: The relevance score.
  /// [metadata]: Optional metadata.
  ChunkSearchResult({required this.text, required this.score, this.metadata});

  /// Alias for [text].
  String get chunk => text;
}

/// Statistics about a vector database or index.
class DatabaseStats {
  /// The total number of documents in the database.
  final int count;

  /// The dimensionality of stored embeddings.
  final int dimension;

  /// Creates a [DatabaseStats].
  ///
  /// [count]: Total document count.
  /// [dimension]: Embedding dimension.
  DatabaseStats({required this.count, required this.dimension});

  /// Alias for [count].
  int get totalDocuments => count;
}

/// Alias for [CactusModel], used when the model is intended for voice
/// applications.
typedef VoiceModel = CactusModel;

/// A single transcription result from a speech-to-text operation.
class CactusTranscriptionResult {
  /// The transcribed text.
  final String text;

  /// Whether this result represents the final transcription for a segment.
  final bool isFinal;

  /// Creates a [CactusTranscriptionResult].
  ///
  /// [text]: The transcribed text.
  /// [isFinal]: Whether this is the final result.
  CactusTranscriptionResult({required this.text, required this.isFinal});

  // For compatibility with stream-based transcribeStream
  /// Returns this result as a single-element stream.
  Stream<CactusTranscriptionResult> get stream => Stream.value(this);

  /// Returns this result as an immediately-resolving future.
  Future<CactusTranscriptionResult> get result => Future.value(this);

  /// Always returns 0.0 for compatibility with the full result interface.
  double get timeToFirstTokenMs => 0.0;

  /// Always returns 0.0 for compatibility with the full result interface.
  double get totalTimeMs => 0.0;
}
