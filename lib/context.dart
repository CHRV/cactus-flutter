import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:cactus/models/types.dart';
import 'package:cactus/services/bindings.dart' as bindings;

List<FunctionCall>? _parseFunctionCalls(Map<String, dynamic> data) {
  final raw = data['function_calls'];
  if (raw == null) return null;
  final List<dynamic> calls = raw as List<dynamic>;
  return calls.map((fc) => FunctionCall(
    name: fc['name'] as String,
    arguments: Map<String, dynamic>.from(fc['arguments'] as Map),
  )).toList();
}

// ---------------------------------------------------------------------------
// Isolate message types (all fields are Sendable / primitive)
// ---------------------------------------------------------------------------

class _TokenMessage {
  final String token;
  const _TokenMessage(this.token);
}

class _CompleteResultMessage {
  final CactusLMCompleteResult result;
  const _CompleteResultMessage(this.result);
}

class _TranscribeResultMessage {
  final CactusSTTTranscribeResult result;
  const _TranscribeResultMessage(this.result);
}

class _ErrorMessage {
  final String message;
  const _ErrorMessage(this.message);
}

// ---------------------------------------------------------------------------
// Args bundles (Sendable)
// ---------------------------------------------------------------------------

class _CompleteIsolateArgs {
  final int handleAddress;
  final String messagesJson;
  final String optionsJson;
  final String toolsJson;
  final Uint8List? pcmData;
  final SendPort sendPort;

  const _CompleteIsolateArgs({
    required this.handleAddress,
    required this.messagesJson,
    required this.optionsJson,
    required this.toolsJson,
    this.pcmData,
    required this.sendPort,
  });
}

class _TranscribeIsolateArgs {
  final int handleAddress;
  final String? audioPath;
  final String prompt;
  final String optionsJson;
  final Uint8List? pcmData;
  final SendPort sendPort;

  const _TranscribeIsolateArgs({
    required this.handleAddress,
    this.audioPath,
    required this.prompt,
    required this.optionsJson,
    this.pcmData,
    required this.sendPort,
  });
}

// ---------------------------------------------------------------------------
// CactusContext
// ---------------------------------------------------------------------------

class CactusContext {
  final Pointer<Void> _handle;

  CactusContext._(this._handle);

  Pointer<Void> get handle => _handle;

  static Future<CactusContext> initContext({
    required String modelPath,
    String? corpusDir,
    bool cacheIndex = true,
  }) async {
    final handle = bindings.cactusInit(modelPath, corpusDir, cacheIndex);
    return CactusContext._(handle);
  }

  static CactusContext fromAddress(int address) {
    return CactusContext._(Pointer.fromAddress(address));
  }

  int get address => _handle.address;

  void destroy() {
    bindings.cactusDestroy(_handle);
  }

  void reset() {
    bindings.cactusReset(_handle);
  }

  void stop() {
    bindings.cactusStop(_handle);
  }

  // -------------------------------------------------------------------------
  // Complete — direct call (blocking); callers that need isolation should
  // use [completeAt] which spawns an isolate.
  // -------------------------------------------------------------------------

  Future<CactusLMCompleteResult> complete({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    CactusTokenCallback? onToken,
    List<int>? pcmData,
  }) async {
    final messagesJson = jsonEncode(messages.map((m) => m.toJson()).toList());
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final toolsJson = tools != null
        ? jsonEncode(tools.map((t) => t.toJson()).toList())
        : '[]';

    final resultJson = bindings.cactusComplete(
      _handle,
      messagesJson,
      optionsJson,
      toolsJson,
      onToken != null
          ? (token, tokenId) {
              onToken(token);
            }
          : null,
      pcmData: pcmData != null ? Uint8List.fromList(pcmData) : null,
    );

    final Map<String, dynamic> data = jsonDecode(resultJson);
    final functionCalls = _parseFunctionCalls(data);
    return CactusLMCompleteResult(
      success: data['success'] ?? false,
      response: data['response'] ?? '',
      thinking: data['thinking'],
      cloudHandoff: data['cloud_handoff'],
      confidence: data['confidence']?.toDouble(),
      timeToFirstTokenMs: data['time_to_first_token_ms']?.toDouble() ?? 0.0,
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      prefillTokens: data['prefill_tokens'] ?? 0,
      prefillTps: data['prefill_tps']?.toDouble() ?? 0.0,
      decodeTokens: data['decode_tokens'] ?? 0,
      decodeTps: data['decode_tps']?.toDouble() ?? 0.0,
      totalTokens: data['total_tokens'] ?? 0,
      ramUsageMb: data['ram_usage_mb']?.toDouble(),
      functionCalls: functionCalls,
    );
  }

  /// Spawns an isolate to run [cactusComplete] without blocking the main
  /// thread. The native [NativeCallable] is created _inside_ the isolate
  /// (required by dart:ffi). Token callbacks are delivered as messages.
  static Future<CactusLMCompleteResult> completeAt({
    required int handleAddress,
    required String messagesJson,
    required String optionsJson,
    required String toolsJson,
    CactusTokenCallback? onToken,
    Uint8List? pcmData,
  }) async {
    final receivePort = ReceivePort();
    final sendPort = receivePort.sendPort;

    await Isolate.spawn(
      _completeInIsolate,
      _CompleteIsolateArgs(
        handleAddress: handleAddress,
        messagesJson: messagesJson,
        optionsJson: optionsJson,
        toolsJson: toolsJson,
        pcmData: pcmData,
        sendPort: sendPort,
      ),
      errorsAreFatal: true,
    );

    CactusLMCompleteResult? result;
    await for (final msg in receivePort) {
      if (msg is _TokenMessage) {
        onToken?.call(msg.token);
      } else if (msg is _CompleteResultMessage) {
        result = msg.result;
        break;
      } else if (msg is _ErrorMessage) {
        throw Exception('Isolate error: ${msg.message}');
      }
    }

    return result!;
  }

  // -------------------------------------------------------------------------
  // Prefill
  // -------------------------------------------------------------------------

  Future<CactusLMPrefillResult> prefill({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    List<int>? pcmData,
  }) async {
    final messagesJson = jsonEncode(messages.map((m) => m.toJson()).toList());
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final toolsJson = tools != null
        ? jsonEncode(tools.map((t) => t.toJson()).toList())
        : '[]';

    final resultJson = bindings.cactusPrefill(
      _handle,
      messagesJson,
      optionsJson,
      toolsJson,
      pcmData: pcmData != null ? Uint8List.fromList(pcmData) : null,
    );

    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusLMPrefillResult(
      success: data['success'] ?? false,
      error: data['error'],
      prefillTokens: data['prefill_tokens'] ?? 0,
      prefillTps: data['prefill_tps']?.toDouble() ?? 0.0,
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

  /// Runs prefill in an isolate via [compute].
  static Future<CactusLMPrefillResult> prefillAt({
    required int handleAddress,
    required String messagesJson,
    required String optionsJson,
    required String toolsJson,
    Uint8List? pcmData,
  }) async {
    return compute(_prefillInIsolate, <String, dynamic>{
      'handle': handleAddress,
      'messagesJson': messagesJson,
      'optionsJson': optionsJson,
      'toolsJson': toolsJson,
      'pcmData': pcmData,
    });
  }

  // -------------------------------------------------------------------------
  // Tokenize
  // -------------------------------------------------------------------------

  Future<CactusLMTokenizeResult> tokenize(String text) async {
    final tokens = bindings.cactusTokenize(_handle, text);
    return CactusLMTokenizeResult(tokens: tokens);
  }

  static CactusLMTokenizeResult tokenizeWithHandle(int address, String text) {
    final context = CactusContext.fromAddress(address);
    final tokens = bindings.cactusTokenize(context.handle, text);
    return CactusLMTokenizeResult(tokens: tokens);
  }

  // -------------------------------------------------------------------------
  // Score window
  // -------------------------------------------------------------------------

  Future<CactusLMScoreWindowResult> scoreWindow({
    required List<int> tokens,
    required int start,
    required int end,
    int contextSize = 512,
  }) async {
    final resultJson = bindings.cactusScoreWindow(
      _handle,
      tokens,
      start,
      end,
      contextSize,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusLMScoreWindowResult(score: data['score']?.toDouble() ?? 0.0);
  }

  static CactusLMScoreWindowResult scoreWindowWithHandle(
    int address,
    List<int> tokens,
    int start,
    int end,
    int contextSize,
  ) {
    final context = CactusContext.fromAddress(address);
    final resultJson = bindings.cactusScoreWindow(
      context.handle,
      tokens,
      start,
      end,
      contextSize,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusLMScoreWindowResult(score: data['score']?.toDouble() ?? 0.0);
  }

  // -------------------------------------------------------------------------
  // Embed text
  // -------------------------------------------------------------------------

  Future<CactusLMEmbedResult> embed(String text,
      {bool normalize = true}) async {
    final embedding = bindings.cactusEmbed(_handle, text, normalize);
    return CactusLMEmbedResult(embedding: embedding.toList());
  }

  static CactusLMEmbedResult embedWithHandle(
      int address, String text, bool normalize) {
    final context = CactusContext.fromAddress(address);
    final embedding = bindings.cactusEmbed(context.handle, text, normalize);
    return CactusLMEmbedResult(embedding: embedding.toList());
  }

  // -------------------------------------------------------------------------
  // Embed image
  // -------------------------------------------------------------------------

  Future<CactusLMImageEmbedResult> embedImage(String imagePath) async {
    final embedding = bindings.cactusImageEmbed(_handle, imagePath);
    return CactusLMImageEmbedResult(embedding: embedding.toList());
  }

  static CactusLMImageEmbedResult imageEmbedWithHandle(
      int address, String imagePath) {
    final context = CactusContext.fromAddress(address);
    final embedding = bindings.cactusImageEmbed(context.handle, imagePath);
    return CactusLMImageEmbedResult(embedding: embedding.toList());
  }

  // -------------------------------------------------------------------------
  // Embed audio
  // -------------------------------------------------------------------------

  Future<CactusSTTAudioEmbedResult> embedAudio(String audioPath) async {
    final embedding = bindings.cactusAudioEmbed(_handle, audioPath);
    return CactusSTTAudioEmbedResult(embedding: embedding.toList());
  }

  static CactusSTTAudioEmbedResult audioEmbedWithHandle(
      int address, String audioPath) {
    final context = CactusContext.fromAddress(address);
    final embedding = bindings.cactusAudioEmbed(context.handle, audioPath);
    return CactusSTTAudioEmbedResult(embedding: embedding.toList());
  }

  // -------------------------------------------------------------------------
  // RAG query
  // -------------------------------------------------------------------------

  Future<CactusLMRagQueryResult> ragQuery(String query, {int topK = 5}) async {
    final resultJson = bindings.cactusRagQuery(_handle, query, topK);
    final Map<String, dynamic> data = jsonDecode(resultJson);
    final List<dynamic> chunksData = data['chunks'] ?? [];
    final chunks = chunksData
        .map((c) => RagQueryChunk(
              score: c['score']?.toDouble() ?? 0.0,
              source: c['source'] ?? '',
              content: c['content'] ?? '',
            ))
        .toList();
    return CactusLMRagQueryResult(chunks: chunks, error: data['error']);
  }

  static CactusLMRagQueryResult ragQueryWithHandle(
      int address, String query, int topK) {
    final context = CactusContext.fromAddress(address);
    final resultJson = bindings.cactusRagQuery(context.handle, query, topK);
    final Map<String, dynamic> data = jsonDecode(resultJson);
    final List<dynamic> chunksData = data['chunks'] ?? [];
    final chunks = chunksData
        .map((c) => RagQueryChunk(
              score: c['score']?.toDouble() ?? 0.0,
              source: c['source'] ?? '',
              content: c['content'] ?? '',
            ))
        .toList();
    return CactusLMRagQueryResult(chunks: chunks, error: data['error']);
  }

  // -------------------------------------------------------------------------
  // Transcribe — direct call (blocking); callers that need isolation should
  // use [transcribeAt] which spawns an isolate.
  // -------------------------------------------------------------------------

  Future<CactusSTTTranscribeResult> transcribe({
    String? audioPath,
    List<int>? pcmData,
    String? prompt,
    CactusSTTTranscribeOptions? options,
    CactusTokenCallback? onToken,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusTranscribe(
      _handle,
      audioPath,
      prompt,
      optionsJson,
      onToken != null
          ? (token, tokenId) {
              onToken(token);
            }
          : null,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );

    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusSTTTranscribeResult(
      success: data['success'] ?? false,
      response: data['response'] ?? '',
      cloudHandoff: data['cloud_handoff'],
      confidence: data['confidence']?.toDouble(),
      timeToFirstTokenMs: data['time_to_first_token_ms']?.toDouble() ?? 0.0,
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      prefillTokens: data['prefill_tokens'] ?? 0,
      prefillTps: data['prefill_tps']?.toDouble() ?? 0.0,
      decodeTokens: data['decode_tokens'] ?? 0,
      decodeTps: data['decode_tps']?.toDouble() ?? 0.0,
      totalTokens: data['total_tokens'] ?? 0,
      ramUsageMb: data['ram_usage_mb']?.toDouble(),
    );
  }

  /// Spawns an isolate to run [cactusTranscribe] without blocking the main
  /// thread. The native [NativeCallable] is created _inside_ the isolate
  /// (required by dart:ffi). Token callbacks are delivered as messages.
  static Future<CactusSTTTranscribeResult> transcribeAt({
    required int handleAddress,
    String? audioPath,
    List<int>? pcmData,
    String? prompt,
    CactusSTTTranscribeOptions? options,
    CactusTokenCallback? onToken,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final receivePort = ReceivePort();
    final sendPort = receivePort.sendPort;

    await Isolate.spawn(
      _transcribeInIsolate,
      _TranscribeIsolateArgs(
        handleAddress: handleAddress,
        audioPath: audioPath,
        prompt: prompt ?? '',
        optionsJson: optionsJson,
        pcmData: pcmData != null ? Uint8List.fromList(pcmData) : null,
        sendPort: sendPort,
      ),
      errorsAreFatal: true,
    );

    CactusSTTTranscribeResult? result;
    await for (final msg in receivePort) {
      if (msg is _TokenMessage) {
        onToken?.call(msg.token);
      } else if (msg is _TranscribeResultMessage) {
        result = msg.result;
        break;
      } else if (msg is _ErrorMessage) {
        throw Exception('Isolate error: ${msg.message}');
      }
    }

    return result!;
  }

  // -------------------------------------------------------------------------
  // Detect language
  // -------------------------------------------------------------------------

  Future<CactusSTTDetectLanguageResult> detectLanguage({
    String? audioPath,
    List<int>? pcmData,
    CactusSTTDetectLanguageOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusDetectLanguage(
      _handle,
      audioPath,
      optionsJson,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusSTTDetectLanguageResult(
      language: data['language'] ?? '',
      confidence: data['confidence']?.toDouble(),
    );
  }

  /// Runs detectLanguage in an isolate via [compute].
  static Future<CactusSTTDetectLanguageResult> detectLanguageAt({
    required int handleAddress,
    String? audioPath,
    List<int>? pcmData,
    CactusSTTDetectLanguageOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    return compute(_detectLanguageInIsolate, <String, dynamic>{
      'handle': handleAddress,
      'audioPath': audioPath,
      'optionsJson': optionsJson,
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  // -------------------------------------------------------------------------
  // VAD
  // -------------------------------------------------------------------------

  Future<CactusAudioVADResult> vad({
    String? audioPath,
    List<int>? pcmData,
    CactusAudioVADOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusVad(
      _handle,
      audioPath,
      optionsJson,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    final List<dynamic> segmentsData = data['segments'] ?? [];
    final segments = segmentsData
        .map((s) => CactusAudioVADSegment(
              start: s['start'] ?? 0,
              end: s['end'] ?? 0,
            ))
        .toList();
    return CactusAudioVADResult(
      segments: segments,
      totalTime: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsage: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

  /// Runs VAD in an isolate via [compute].
  static Future<CactusAudioVADResult> vadAt({
    required int handleAddress,
    String? audioPath,
    Uint8List? pcmData,
    CactusAudioVADOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    return compute(_vadInIsolate, <String, dynamic>{
      'handle': handleAddress,
      'audioPath': audioPath,
      'optionsJson': optionsJson,
      'pcmData': pcmData,
    });
  }

  // -------------------------------------------------------------------------
  // Diarize
  // -------------------------------------------------------------------------

  Future<CactusAudioDiarizeResult> diarize({
    String? audioPath,
    List<int>? pcmData,
    CactusAudioDiarizeOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusDiarize(
      _handle,
      audioPath,
      optionsJson,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusAudioDiarizeResult(
      success: data['success'] ?? false,
      error: data['error'],
      numSpeakers: data['num_speakers'] ?? 0,
      scores: (data['scores'] as List<dynamic>?)
              ?.map((e) => e.toDouble() as double)
              .toList() ??
          [],
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

  /// Runs diarize in an isolate via [compute].
  static Future<CactusAudioDiarizeResult> diarizeAt({
    required int handleAddress,
    String? audioPath,
    Uint8List? pcmData,
    CactusAudioDiarizeOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    return compute(_diarizeInIsolate, <String, dynamic>{
      'handle': handleAddress,
      'audioPath': audioPath,
      'optionsJson': optionsJson,
      'pcmData': pcmData,
    });
  }

  // -------------------------------------------------------------------------
  // Embed speaker
  // -------------------------------------------------------------------------

  Future<CactusAudioEmbedSpeakerResult> embedSpeaker({
    String? audioPath,
    List<int>? pcmData,
    CactusAudioEmbedSpeakerOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusEmbedSpeaker(
      _handle,
      audioPath,
      optionsJson,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusAudioEmbedSpeakerResult(
      success: data['success'] ?? false,
      error: data['error'],
      embedding: (data['embedding'] as List<dynamic>?)
              ?.map((e) => e.toDouble() as double)
              .toList() ??
          [],
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

  /// Runs embedSpeaker in an isolate via [compute].
  static Future<CactusAudioEmbedSpeakerResult> embedSpeakerAt({
    required int handleAddress,
    String? audioPath,
    Uint8List? pcmData,
    CactusAudioEmbedSpeakerOptions? options,
  }) async {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    return compute(_embedSpeakerInIsolate, <String, dynamic>{
      'handle': handleAddress,
      'audioPath': audioPath,
      'optionsJson': optionsJson,
      'pcmData': pcmData,
    });
  }

  // -------------------------------------------------------------------------
  // Stream transcription
  // -------------------------------------------------------------------------

  int streamTranscribeStart({CactusSTTStreamTranscribeStartOptions? options}) {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final stream = bindings.cactusStreamTranscribeStart(_handle, optionsJson);
    return stream.address;
  }

  Future<CactusSTTStreamTranscribeProcessResult> streamTranscribeProcess({
    required int streamAddress,
    required List<int> pcmData,
  }) async {
    final resultJson = bindings.cactusStreamTranscribeProcess(
      Pointer.fromAddress(streamAddress),
      Uint8List.fromList(pcmData),
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusSTTStreamTranscribeProcessResult(
      success: data['success'] ?? false,
      confirmed: data['confirmed'] ?? '',
      pending: data['pending'] ?? '',
      bufferDurationMs: data['buffer_duration_ms']?.toDouble(),
      confidence: data['confidence']?.toDouble(),
      cloudHandoff: data['cloud_handoff'],
      timeToFirstTokenMs: data['time_to_first_token_ms']?.toDouble(),
      totalTimeMs: data['total_time_ms']?.toDouble(),
      prefillTokens: data['prefill_tokens'],
      prefillTps: data['prefill_tps']?.toDouble(),
      decodeTokens: data['decode_tokens'],
      decodeTps: data['decode_tps']?.toDouble(),
      totalTokens: data['total_tokens'],
      ramUsageMb: data['ram_usage_mb']?.toDouble(),
    );
  }

  static CactusSTTStreamTranscribeProcessResult
      streamTranscribeProcessWithHandle(
    int streamAddress,
    List<int> pcmData,
  ) {
    final resultJson = bindings.cactusStreamTranscribeProcess(
      Pointer.fromAddress(streamAddress),
      Uint8List.fromList(pcmData),
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusSTTStreamTranscribeProcessResult(
      success: data['success'] ?? false,
      confirmed: data['confirmed'] ?? '',
      pending: data['pending'] ?? '',
      bufferDurationMs: data['buffer_duration_ms']?.toDouble(),
      confidence: data['confidence']?.toDouble(),
      cloudHandoff: data['cloud_handoff'],
      timeToFirstTokenMs: data['time_to_first_token_ms']?.toDouble(),
      totalTimeMs: data['total_time_ms']?.toDouble(),
      prefillTokens: data['prefill_tokens'],
      prefillTps: data['prefill_tps']?.toDouble(),
      decodeTokens: data['decode_tokens'],
      decodeTps: data['decode_tps']?.toDouble(),
      totalTokens: data['total_tokens'],
      ramUsageMb: data['ram_usage_mb']?.toDouble(),
    );
  }

  Future<CactusSTTStreamTranscribeStopResult> streamTranscribeStop(
      int streamAddress) async {
    final resultJson = bindings.cactusStreamTranscribeStop(
      Pointer.fromAddress(streamAddress),
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusSTTStreamTranscribeStopResult(
      success: data['success'] ?? false,
      confirmed: data['confirmed'] ?? '',
    );
  }

  static CactusSTTStreamTranscribeStopResult streamTranscribeStopWithHandle(
      int streamAddress) {
    final resultJson = bindings.cactusStreamTranscribeStop(
      Pointer.fromAddress(streamAddress),
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusSTTStreamTranscribeStopResult(
      success: data['success'] ?? false,
      confirmed: data['confirmed'] ?? '',
    );
  }
}

// ===========================================================================
// Top-level isolate entry-point functions
// ===========================================================================
//
// IMPORTANT: These run inside a spawned isolate.  [NativeCallable] objects
// MUST be created here (not on the main thread) per dart:ffi requirements.
// ===========================================================================

/// Entry point for [CactusContext.completeAt] — runs in spawned isolate.
/// Calls native `cactus_complete` with a Dart closure callback and streams
/// tokens + final result back via [SendPort].
void _completeInIsolate(_CompleteIsolateArgs args) {
  final context = CactusContext.fromAddress(args.handleAddress);

  try {
    final resultJson = bindings.cactusComplete(
      context.handle,
      args.messagesJson,
      args.optionsJson,
      args.toolsJson,
      (token, tokenId) {
        args.sendPort.send(_TokenMessage(token));
      },
      pcmData: args.pcmData,
    );

    final Map<String, dynamic> data = jsonDecode(resultJson);
    final functionCalls = _parseFunctionCalls(data);
    args.sendPort.send(
      _CompleteResultMessage(
        CactusLMCompleteResult(
          success: data['success'] ?? false,
          response: data['response'] ?? '',
          thinking: data['thinking'],
          cloudHandoff: data['cloud_handoff'],
          confidence: data['confidence']?.toDouble(),
          timeToFirstTokenMs: data['time_to_first_token_ms']?.toDouble() ?? 0.0,
          totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
          prefillTokens: data['prefill_tokens'] ?? 0,
          prefillTps: data['prefill_tps']?.toDouble() ?? 0.0,
          decodeTokens: data['decode_tokens'] ?? 0,
          decodeTps: data['decode_tps']?.toDouble() ?? 0.0,
          totalTokens: data['total_tokens'] ?? 0,
          ramUsageMb: data['ram_usage_mb']?.toDouble(),
          functionCalls: functionCalls,
        ),
      ),
    );
  } catch (e) {
    args.sendPort.send(_ErrorMessage(e.toString()));
  }
}

/// Entry point for [CactusContext.transcribeAt] — runs in spawned isolate.
/// Calls native `cactus_transcribe` with a Dart closure callback and streams
/// tokens + final result back via [SendPort].
void _transcribeInIsolate(_TranscribeIsolateArgs args) {
  final context = CactusContext.fromAddress(args.handleAddress);

  try {
    final resultJson = bindings.cactusTranscribe(
      context.handle,
      args.audioPath,
      args.prompt,
      args.optionsJson,
      (token, tokenId) {
        args.sendPort.send(_TokenMessage(token));
      },
      args.pcmData,
    );

    final Map<String, dynamic> data = jsonDecode(resultJson);
    args.sendPort.send(
      _TranscribeResultMessage(
        CactusSTTTranscribeResult(
          success: data['success'] ?? false,
          response: data['response'] ?? '',
          cloudHandoff: data['cloud_handoff'],
          confidence: data['confidence']?.toDouble(),
          timeToFirstTokenMs: data['time_to_first_token_ms']?.toDouble() ?? 0.0,
          totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
          prefillTokens: data['prefill_tokens'] ?? 0,
          prefillTps: data['prefill_tps']?.toDouble() ?? 0.0,
          decodeTokens: data['decode_tokens'] ?? 0,
          decodeTps: data['decode_tps']?.toDouble() ?? 0.0,
          totalTokens: data['total_tokens'] ?? 0,
          ramUsageMb: data['ram_usage_mb']?.toDouble(),
        ),
      ),
    );
  } catch (e) {
    args.sendPort.send(_ErrorMessage(e.toString()));
  }
}

/// Entry point for prefill — runs via compute().
CactusLMPrefillResult _prefillInIsolate(Map<String, dynamic> params) {
  final context = CactusContext.fromAddress(params['handle'] as int);
  final resultJson = bindings.cactusPrefill(
    context.handle,
    params['messagesJson'] as String,
    params['optionsJson'] as String,
    params['toolsJson'] as String,
    pcmData: params['pcmData'] as Uint8List?,
  );
  final Map<String, dynamic> data = jsonDecode(resultJson);
  return CactusLMPrefillResult(
    success: data['success'] ?? false,
    error: data['error'],
    prefillTokens: data['prefill_tokens'] ?? 0,
    prefillTps: data['prefill_tps']?.toDouble() ?? 0.0,
    totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
    ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
  );
}

/// Entry point for detectLanguage — runs via compute().
CactusSTTDetectLanguageResult _detectLanguageInIsolate(
    Map<String, dynamic> params) {
  final context = CactusContext.fromAddress(params['handle'] as int);
  final resultJson = bindings.cactusDetectLanguage(
    context.handle,
    params['audioPath'] as String?,
    params['optionsJson'] as String,
    params['pcmData'] as Uint8List?,
  );
  final Map<String, dynamic> data = jsonDecode(resultJson);
  return CactusSTTDetectLanguageResult(
    language: data['language'] ?? '',
    confidence: data['confidence']?.toDouble(),
  );
}

/// Entry point for vad — runs via compute().
CactusAudioVADResult _vadInIsolate(Map<String, dynamic> params) {
  final context = CactusContext.fromAddress(params['handle'] as int);
  final resultJson = bindings.cactusVad(
    context.handle,
    params['audioPath'] as String?,
    params['optionsJson'] as String,
    params['pcmData'] as Uint8List?,
  );
  final Map<String, dynamic> data = jsonDecode(resultJson);
  final List<dynamic> segmentsData = data['segments'] ?? [];
  final segments = segmentsData
      .map((s) => CactusAudioVADSegment(
            start: s['start'] ?? 0,
            end: s['end'] ?? 0,
          ))
      .toList();
  return CactusAudioVADResult(
    segments: segments,
    totalTime: data['total_time_ms']?.toDouble() ?? 0.0,
    ramUsage: data['ram_usage_mb']?.toDouble() ?? 0.0,
  );
}

/// Entry point for diarize — runs via compute().
CactusAudioDiarizeResult _diarizeInIsolate(Map<String, dynamic> params) {
  final context = CactusContext.fromAddress(params['handle'] as int);
  final resultJson = bindings.cactusDiarize(
    context.handle,
    params['audioPath'] as String?,
    params['optionsJson'] as String,
    params['pcmData'] as Uint8List?,
  );
  final Map<String, dynamic> data = jsonDecode(resultJson);
  return CactusAudioDiarizeResult(
    success: data['success'] ?? false,
    error: data['error'],
    numSpeakers: data['num_speakers'] ?? 0,
    scores: (data['scores'] as List<dynamic>?)
            ?.map((e) => e.toDouble() as double)
            .toList() ??
        [],
    totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
    ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
  );
}

/// Entry point for embedSpeaker — runs via compute().
CactusAudioEmbedSpeakerResult _embedSpeakerInIsolate(
    Map<String, dynamic> params) {
  final context = CactusContext.fromAddress(params['handle'] as int);
  final resultJson = bindings.cactusEmbedSpeaker(
    context.handle,
    params['audioPath'] as String?,
    params['optionsJson'] as String,
    params['pcmData'] as Uint8List?,
  );
  final Map<String, dynamic> data = jsonDecode(resultJson);
  return CactusAudioEmbedSpeakerResult(
    success: data['success'] ?? false,
    error: data['error'],
    embedding: (data['embedding'] as List<dynamic>?)
            ?.map((e) => e.toDouble() as double)
            .toList() ??
        [],
    totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
    ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
  );
}

// ===========================================================================
// CactusIndex (wrapper around native cactus_index_t)
// ===========================================================================

class CactusIndex {
  final Pointer<Void> _handle;

  CactusIndex._(this._handle);

  Pointer<Void> get handle => _handle;

  static Future<CactusIndex> init({
    required String indexPath,
    required int embeddingDim,
  }) async {
    final handle = bindings.cactusIndexInit(indexPath, embeddingDim);
    return CactusIndex._(handle);
  }

  static CactusIndex fromAddress(int address) {
    return CactusIndex._(Pointer.fromAddress(address));
  }

  void add({
    required List<int> ids,
    required List<String> documents,
    required List<List<double>> embeddings,
    required int embeddingDim,
    List<String>? metadatas,
  }) {
    bindings.cactusIndexAdd(_handle, ids, documents, embeddings, metadatas);
  }

  void delete({required List<int> ids}) {
    bindings.cactusIndexDelete(_handle, ids);
  }

  CactusIndexGetResult get({required List<int> ids}) {
    // Query each ID individually to gracefully handle deleted/missing documents.
    final documents = <String>[];
    final metadatas = <String>[];
    final embeddings = <List<double>>[];

    for (final id in ids) {
      try {
        final resultJson = bindings.cactusIndexGet(_handle, [id]);
        final Map<String, dynamic> data = jsonDecode(resultJson);
        final List<dynamic> results = data['results'] ?? [];
        if (results.isNotEmpty) {
          final r = results[0];
          documents.add(r['document'] ?? '');
          metadatas.add(r['metadata'] ?? '');
          embeddings.add((r['embedding'] as List<dynamic>?)
                  ?.map((e) => e.toDouble() as double)
                  .toList() ??
              []);
        } else {
          documents.add('');
          metadatas.add('');
          embeddings.add([]);
        }
      } catch (_) {
        documents.add('');
        metadatas.add('');
        embeddings.add([]);
      }
    }

    return CactusIndexGetResult(
      documents: documents,
      metadatas: metadatas,
      embeddings: embeddings,
    );
  }

  CactusIndexQueryResult query({
    required List<List<double>> embeddings,
    required int embeddingDim,
    CactusIndexQueryOptions? options,
  }) {
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultIds = <List<int>>[];
    final resultScores = <List<double>>[];

    for (final emb in embeddings) {
      final resultJson = bindings.cactusIndexQuery(_handle, emb, optionsJson);
      final Map<String, dynamic> data = jsonDecode(resultJson);
      final List<dynamic> results = data['results'] ?? [];

      final ids = <int>[];
      final scores = <double>[];

      for (final r in results) {
        ids.add(r['id'] ?? 0);
        scores.add(r['score']?.toDouble() ?? 0.0);
      }

      resultIds.add(ids);
      resultScores.add(scores);
    }

    return CactusIndexQueryResult(ids: resultIds, scores: resultScores);
  }

  void compact() {
    bindings.cactusIndexCompact(_handle);
  }

  void destroy() {
    bindings.cactusIndexDestroy(_handle);
  }
}
