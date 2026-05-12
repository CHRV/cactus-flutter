import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cactus/models/types.dart';
import 'package:cactus/src/services/bindings.dart' as bindings;

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

  Future<CactusLMCompleteResult> complete({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    CactusTokenCallback? onToken,
    List<int>? pcmData,
  }) async {
    final messagesJson = jsonEncode(messages.map((m) => m.toJson()).toList());
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final toolsJson = tools != null ? jsonEncode(tools.map((t) => t.toJson()).toList()) : '[]';

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
    );
  }

  static Future<CactusLMCompleteResult> completeAt({
    required int handleAddress,
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    CactusTokenCallback? onToken,
    List<int>? pcmData,
  }) {
    final context = CactusContext.fromAddress(handleAddress);
    return context.complete(
      messages: messages,
      options: options,
      tools: tools,
      onToken: onToken,
      pcmData: pcmData,
    );
  }

  Future<CactusLMPrefillResult> prefill({
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    List<int>? pcmData,
  }) async {
    final messagesJson = jsonEncode(messages.map((m) => m.toJson()).toList());
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final toolsJson = tools != null ? jsonEncode(tools.map((t) => t.toJson()).toList()) : '[]';

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

  static Future<CactusLMPrefillResult> prefillAt({
    required int handleAddress,
    required List<CactusLMMessage> messages,
    CactusLMCompleteOptions? options,
    List<CactusLMTool>? tools,
    List<int>? pcmData,
  }) {
    final context = CactusContext.fromAddress(handleAddress);
    return context.prefill(
      messages: messages,
      options: options,
      tools: tools,
      pcmData: pcmData,
    );
  }

  Future<CactusLMTokenizeResult> tokenize(String text) async {
    final tokens = bindings.cactusTokenize(_handle, text);
    return CactusLMTokenizeResult(tokens: tokens);
  }

  static CactusLMTokenizeResult tokenizeWithHandle(int address, String text) {
    final context = CactusContext.fromAddress(address);
    final tokens = bindings.cactusTokenize(context.handle, text);
    return CactusLMTokenizeResult(tokens: tokens);
  }

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

  Future<CactusLMEmbedResult> embed(String text, {bool normalize = true}) async {
    final embedding = bindings.cactusEmbed(_handle, text, normalize);
    return CactusLMEmbedResult(embedding: embedding.toList());
  }

  static CactusLMEmbedResult embedWithHandle(int address, String text, bool normalize) {
    final context = CactusContext.fromAddress(address);
    final embedding = bindings.cactusEmbed(context.handle, text, normalize);
    return CactusLMEmbedResult(embedding: embedding.toList());
  }

  Future<CactusLMImageEmbedResult> embedImage(String imagePath) async {
    final embedding = bindings.cactusImageEmbed(_handle, imagePath);
    return CactusLMImageEmbedResult(embedding: embedding.toList());
  }

  static CactusLMImageEmbedResult imageEmbedWithHandle(int address, String imagePath) {
    final context = CactusContext.fromAddress(address);
    final embedding = bindings.cactusImageEmbed(context.handle, imagePath);
    return CactusLMImageEmbedResult(embedding: embedding.toList());
  }

  Future<CactusSTTAudioEmbedResult> embedAudio(String audioPath) async {
    final embedding = bindings.cactusAudioEmbed(_handle, audioPath);
    return CactusSTTAudioEmbedResult(embedding: embedding.toList());
  }

  static CactusSTTAudioEmbedResult audioEmbedWithHandle(int address, String audioPath) {
    final context = CactusContext.fromAddress(address);
    final embedding = bindings.cactusAudioEmbed(context.handle, audioPath);
    return CactusSTTAudioEmbedResult(embedding: embedding.toList());
  }

  Future<CactusLMRagQueryResult> ragQuery(String query, {int topK = 5}) async {
    final resultJson = bindings.cactusRagQuery(_handle, query, topK);
    final Map<String, dynamic> data = jsonDecode(resultJson);
    final List<dynamic> chunksData = data['chunks'] ?? [];
    final chunks = chunksData.map((c) => RagQueryChunk(
      score: c['score']?.toDouble() ?? 0.0,
      source: c['source'] ?? '',
      content: c['content'] ?? '',
    )).toList();
    return CactusLMRagQueryResult(chunks: chunks, error: data['error']);
  }

  static CactusLMRagQueryResult ragQueryWithHandle(int address, String query, int topK) {
    final context = CactusContext.fromAddress(address);
    final resultJson = bindings.cactusRagQuery(context.handle, query, topK);
    final Map<String, dynamic> data = jsonDecode(resultJson);
    final List<dynamic> chunksData = data['chunks'] ?? [];
    final chunks = chunksData.map((c) => RagQueryChunk(
      score: c['score']?.toDouble() ?? 0.0,
      source: c['source'] ?? '',
      content: c['content'] ?? '',
    )).toList();
    return CactusLMRagQueryResult(chunks: chunks, error: data['error']);
  }

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

  static Future<CactusSTTTranscribeResult> transcribeAt({
    required int handleAddress,
    String? audioPath,
    List<int>? pcmData,
    String? prompt,
    CactusSTTTranscribeOptions? options,
    CactusTokenCallback? onToken,
  }) {
    final context = CactusContext.fromAddress(handleAddress);
    return context.transcribe(
      audioPath: audioPath,
      pcmData: pcmData,
      prompt: prompt,
      options: options,
      onToken: onToken,
    );
  }

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
    final segments = segmentsData.map((s) => CactusAudioVADSegment(
      start: s['start'] ?? 0,
      end: s['end'] ?? 0,
    )).toList();
    return CactusAudioVADResult(
      segments: segments,
      totalTime: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsage: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

  static CactusAudioVADResult vadWithHandle(
    int address,
    String? audioPath,
    List<int>? pcmData,
    CactusAudioVADOptions? options,
  ) {
    final context = CactusContext.fromAddress(address);
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusVad(
      context.handle,
      audioPath,
      optionsJson,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    final List<dynamic> segmentsData = data['segments'] ?? [];
    final segments = segmentsData.map((s) => CactusAudioVADSegment(
      start: s['start'] ?? 0,
      end: s['end'] ?? 0,
    )).toList();
    return CactusAudioVADResult(
      segments: segments,
      totalTime: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsage: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

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
      scores: (data['scores'] as List<dynamic>?)?.map((e) => e.toDouble() as double).toList() ?? [],
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

  static CactusAudioDiarizeResult diarizeWithHandle(
    int address,
    String? audioPath,
    List<int>? pcmData,
    CactusAudioDiarizeOptions? options,
  ) {
    final context = CactusContext.fromAddress(address);
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusDiarize(
      context.handle,
      audioPath,
      optionsJson,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusAudioDiarizeResult(
      success: data['success'] ?? false,
      error: data['error'],
      numSpeakers: data['num_speakers'] ?? 0,
      scores: (data['scores'] as List<dynamic>?)?.map((e) => e.toDouble() as double).toList() ?? [],
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

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
      embedding: (data['embedding'] as List<dynamic>?)?.map((e) => e.toDouble() as double).toList() ?? [],
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

  static CactusAudioEmbedSpeakerResult embedSpeakerWithHandle(
    int address,
    String? audioPath,
    List<int>? pcmData,
    CactusAudioEmbedSpeakerOptions? options,
  ) {
    final context = CactusContext.fromAddress(address);
    final optionsJson = options != null ? jsonEncode(options.toJson()) : '{}';
    final resultJson = bindings.cactusEmbedSpeaker(
      context.handle,
      audioPath,
      optionsJson,
      pcmData != null ? Uint8List.fromList(pcmData) : null,
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusAudioEmbedSpeakerResult(
      success: data['success'] ?? false,
      error: data['error'],
      embedding: (data['embedding'] as List<dynamic>?)?.map((e) => e.toDouble() as double).toList() ?? [],
      totalTimeMs: data['total_time_ms']?.toDouble() ?? 0.0,
      ramUsageMb: data['ram_usage_mb']?.toDouble() ?? 0.0,
    );
  }

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

  static CactusSTTStreamTranscribeProcessResult streamTranscribeProcessWithHandle(
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

  Future<CactusSTTStreamTranscribeStopResult> streamTranscribeStop(int streamAddress) async {
    final resultJson = bindings.cactusStreamTranscribeStop(
      Pointer.fromAddress(streamAddress),
    );
    final Map<String, dynamic> data = jsonDecode(resultJson);
    return CactusSTTStreamTranscribeStopResult(
      success: data['success'] ?? false,
      confirmed: data['confirmed'] ?? '',
    );
  }

  static CactusSTTStreamTranscribeStopResult streamTranscribeStopWithHandle(int streamAddress) {
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
    final resultJson = bindings.cactusIndexGet(_handle, ids);
    final Map<String, dynamic> data = jsonDecode(resultJson);
    final List<dynamic> results = data['results'] ?? [];

    final documents = <String>[];
    final metadatas = <String>[];
    final embeddings = <List<double>>[];

    for (final r in results) {
      documents.add(r['document'] ?? '');
      metadatas.add(r['metadata'] ?? '');
      embeddings.add((r['embedding'] as List<dynamic>?)?.map((e) => e.toDouble() as double).toList() ?? []);
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
