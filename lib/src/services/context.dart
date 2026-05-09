import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cactus/models/types.dart';
import 'package:cactus/models/tools.dart';
import 'package:cactus/src/models/binding.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'bindings.dart' as bindings;

// Global callback storage for streaming completions
CactusTokenCallback? _activeTokenCallback;

// Static callback function that can be used with Pointer.fromFunction
@pragma('vm:entry-point')
void _staticTokenCallbackDispatcher(Pointer<Utf8> tokenC, int tokenId, Pointer<Void> userData) {
  try {
    final callback = _activeTokenCallback;
    if (callback != null) {
      final tokenString = tokenC.toDartString();
      callback(tokenString);
    }
  } catch (e) {
    debugPrint('Token callback error: $e');
  }
}

Future<(int?, String)> _initContextInIsolate(Map<String, dynamic> params) async {
  final modelPath = params['modelPath'] as String;

  try {
    debugPrint('Initializing context with model: $modelPath');
    final modelPathC = modelPath.toNativeUtf8(allocator: calloc);
    try {
      final handle = bindings.cactusInit(modelPathC, nullptr, false);
      if (handle != nullptr) {
        return (handle.address, 'Context initialized successfully');
      } else {
        return (null, 'Failed to initialize context');
      }
    } finally {
      calloc.free(modelPathC);
    }
  } catch (e) {
    return (null, 'Exception during context initialization: $e');
  }
}

Future<CactusCompletionResult> _completionInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final messagesJson = params['messagesJson'] as String;
  final optionsJson = params['optionsJson'] as String;
  final toolsJson = params['toolsJson'] as String?;
  final bufferSize = params['bufferSize'] as int;
  final hasCallback = params['hasCallback'] as bool;
  final SendPort? replyPort = params['replyPort'] as SendPort?;
  final List<int>? pcmData = params['pcmData'] as List<int>?;

  final responseBuffer = calloc<Uint8>(bufferSize);
  final messagesJsonC = messagesJson.toNativeUtf8(allocator: calloc);
  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);
  final toolsJsonC = toolsJson?.toNativeUtf8(allocator: calloc);

  Pointer<Uint8>? pcmBufferPtr;
  if (pcmData != null) {
    final Uint8List pcmBytes = pcmData is Uint8List ? pcmData : Uint8List.fromList(pcmData);
    pcmBufferPtr = calloc<Uint8>(pcmBytes.length);
    final nativeList = pcmBufferPtr.asTypedList(pcmBytes.length);
    nativeList.setAll(0, pcmBytes);
  }

  Pointer<NativeFunction<CactusTokenCallbackNative>>? callbackPointer;

  try {
    if (hasCallback && replyPort != null) {
      _activeTokenCallback = (token) {
        replyPort.send({'type': 'token', 'data': token});
        return true;
      };
      
      callbackPointer = Pointer.fromFunction<CactusTokenCallbackNative>(
        _staticTokenCallbackDispatcher
      );
    }

    final result = bindings.cactusComplete(
      Pointer.fromAddress(handle),
      messagesJsonC,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      optionsJsonC,
      toolsJsonC ?? nullptr,
      callbackPointer ?? nullptr,
      nullptr,
      pcmBufferPtr ?? nullptr,
      pcmData?.length ?? 0,
    );

    debugPrint('Received completion result code: $result');

    if (result > 0) {
      final responseText = utf8.decode(responseBuffer.asTypedList(result), allowMalformed: true).trim();
      
      try {
        final jsonResponse = jsonDecode(responseText) as Map<String, dynamic>;
        final success = jsonResponse['success'] as bool? ?? true;
        final response = jsonResponse['response'] as String? ?? responseText;
        final timeToFirstTokenMs = (jsonResponse['time_to_first_token_ms'] as num?)?.toDouble() ?? 0.0;
        final totalTimeMs = (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0;
        final tokensPerSecond = (jsonResponse['tokens_per_second'] as num?)?.toDouble() ?? 
            ((jsonResponse['decode_tps'] as num?)?.toDouble() ?? 0.0);
        final prefillTokens = jsonResponse['prefill_tokens'] as int? ?? 0;
        final decodeTokens = jsonResponse['decode_tokens'] as int? ?? 0;
        final totalTokens = jsonResponse['total_tokens'] as int? ?? 0;
        final confidence = (jsonResponse['confidence'] as num?)?.toDouble() ?? 0.0;
        final cloudHandoff = jsonResponse['cloud_handoff'] as bool? ?? false;
        final thinking = jsonResponse['thinking'] as String?;
        final prefillTps = (jsonResponse['prefill_tps'] as num?)?.toDouble() ?? 0.0;
        final decodeTps = (jsonResponse['decode_tps'] as num?)?.toDouble() ?? 0.0;
        final ramUsageMb = (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0;
        
        // Parse tool calls
        List<ToolCall> toolCalls = [];
        if (jsonResponse['function_calls'] != null) {
          final toolCallsJson = jsonResponse['function_calls'] as List<dynamic>;
          toolCalls = toolCallsJson
              .map((toolCallJson) => ToolCall.fromJson(toolCallJson as Map<String, dynamic>))
              .toList();
        }

        return CactusCompletionResult(
          success: success,
          response: response,
          timeToFirstTokenMs: timeToFirstTokenMs,
          totalTimeMs: totalTimeMs,
          tokensPerSecond: tokensPerSecond,
          prefillTokens: prefillTokens,
          decodeTokens: decodeTokens,
          totalTokens: totalTokens,
          toolCalls: toolCalls,
          confidence: confidence,
          cloudHandoff: cloudHandoff,
          thinking: thinking,
          prefillTps: prefillTps,
          decodeTps: decodeTps,
          ramUsageMb: ramUsageMb,
        );
      } catch (e) {
        debugPrint('Unable to parse the response json: $e');
        return CactusCompletionResult(
          success: false,
          response: 'Error: Unable to parse the response',
          timeToFirstTokenMs: 0.0,
          totalTimeMs: 0.0,
          tokensPerSecond: 0.0,
          prefillTokens: 0,
          decodeTokens: 0,
          totalTokens: 0,
          toolCalls: [],
          confidence: 0.0,
          cloudHandoff: false,
          prefillTps: 0.0,
          decodeTps: 0.0,
          ramUsageMb: 0.0,
        );
      }
    } else {
      return CactusCompletionResult(
        success: false,
        response: 'Error: completion failed with code $result',
        timeToFirstTokenMs: 0.0,
        totalTimeMs: 0.0,
        tokensPerSecond: 0.0,
        prefillTokens: 0,
        decodeTokens: 0,
        totalTokens: 0,
        toolCalls: [],
        confidence: 0.0,
        cloudHandoff: false,
        prefillTps: 0.0,
        decodeTps: 0.0,
        ramUsageMb: 0.0,
      );
    }
  } finally {
    _activeTokenCallback = null;
    calloc.free(responseBuffer);
    calloc.free(messagesJsonC);
    calloc.free(optionsJsonC);
    if (toolsJsonC != null) {
      calloc.free(toolsJsonC);
    }
    if (pcmBufferPtr != null) {
      calloc.free(pcmBufferPtr);
    }
  }
}

Future<CactusEmbeddingResult> _generateEmbeddingInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final text = params['text'] as String;
  final bufferSize = params['bufferSize'] as int;

  final textC = text.toNativeUtf8(allocator: calloc);
  final embeddingDimPtr = calloc<IntPtr>();
  final embeddingsBuffer = calloc<Float>(bufferSize);

  try {
    debugPrint('Generating embedding for text: ${text.length > 50 ? "${text.substring(0, 50)}..." : text}');

    // Calculate buffer size in bytes (bufferSize * sizeof(float))
    final bufferSizeInBytes = bufferSize * 4;

    final result = bindings.cactusEmbed(
      Pointer.fromAddress(handle),
      textC,
      embeddingsBuffer,
      bufferSizeInBytes,
      embeddingDimPtr,
      false,
    );

    debugPrint('Received embedding result code: $result');

    if (result > 0) {
      final actualEmbeddingDim = embeddingDimPtr.value;
      debugPrint('Actual embedding dimension: $actualEmbeddingDim');

      if (actualEmbeddingDim > bufferSize) {
        return CactusEmbeddingResult(
          success: false,
          embeddings: [],
          dimension: 0,
          errorMessage: 'Embedding dimension ($actualEmbeddingDim) exceeds allocated buffer size ($bufferSize)',
        );
      }

      final embeddings = <double>[];
      for (int i = 0; i < actualEmbeddingDim; i++) {
        embeddings.add(embeddingsBuffer[i]);
      }

      debugPrint('Successfully extracted ${embeddings.length} embedding values');

      return CactusEmbeddingResult(
        success: true,
        embeddings: embeddings,
        dimension: actualEmbeddingDim,
      );
    } else {
      return CactusEmbeddingResult(
        success: false,
        embeddings: [],
        dimension: 0,
        errorMessage: 'Embedding generation failed with code $result',
      );
    }
  } catch (e) {
    debugPrint('Exception during embedding generation: $e');
    return CactusEmbeddingResult(
      success: false,
      embeddings: [],
      dimension: 0,
      errorMessage: 'Exception: $e',
    );
  } finally {
    calloc.free(textC);
    calloc.free(embeddingDimPtr);
    calloc.free(embeddingsBuffer);
  }
}

Future<CactusTranscriptionResult> _transcribeInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final audioFilePath = params['audioFilePath'] as String?;
  final prompt = params['prompt'] as String;
  final optionsJson = params['optionsJson'] as String;
  final bufferSize = params['bufferSize'] as int;
  final hasCallback = params['hasCallback'] as bool;
  final SendPort? replyPort = params['replyPort'] as SendPort?;
  final List<int>? pcmData = params['pcmData'] as List<int>?;

  if (audioFilePath == null && pcmData == null) {
    debugPrint('ERROR: Neither audio file path nor PCM buffer provided');
    return CactusTranscriptionResult(
      success: false,
      text: '',
      errorMessage: 'Either audio file path or PCM buffer must be provided'
    );
  }

  if (audioFilePath != null) {
    final audioFile = File(audioFilePath);
    if (!audioFile.existsSync()) {
      debugPrint('ERROR: Audio file does not exist at path: $audioFilePath');
      return CactusTranscriptionResult(
        success: false,
        text: '',
        errorMessage: 'Audio file not found: $audioFilePath'
      );
    }

    final fileSize = audioFile.lengthSync();
    debugPrint('Audio file exists, size: $fileSize bytes');
  } else {
    debugPrint('Using PCM buffer, size: ${pcmData!.length} bytes');
  }

  final responseBuffer = calloc<Uint8>(bufferSize);
  final audioFilePathC = audioFilePath?.toNativeUtf8(allocator: calloc);
  final promptC = prompt.toNativeUtf8(allocator: calloc);
  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);

  Pointer<Uint8>? pcmBufferPtr;
  if (pcmData != null) {
    final Uint8List pcmBytes = pcmData is Uint8List ? pcmData : Uint8List.fromList(pcmData);
    pcmBufferPtr = calloc<Uint8>(pcmBytes.length);
    final nativeList = pcmBufferPtr.asTypedList(pcmBytes.length);
    nativeList.setAll(0, pcmBytes);
  }

  Pointer<NativeFunction<CactusTokenCallbackNative>>? callbackPointer;

  try {
    if (hasCallback && replyPort != null) {
      _activeTokenCallback = (token) {
        replyPort.send({'type': 'token', 'data': token});
        return true;
      };

      callbackPointer = Pointer.fromFunction<CactusTokenCallbackNative>(
        _staticTokenCallbackDispatcher
      );
    }

    final result = bindings.cactusTranscribe(
      Pointer.fromAddress(handle),
      audioFilePathC ?? nullptr,
      promptC,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      optionsJsonC,
      callbackPointer ?? nullptr,
      nullptr,
      pcmBufferPtr ?? nullptr,
      pcmData?.length ?? 0,
    );

    if (result <= 0) {
      // Try to read any error message from the buffer
      try {
        final errorText = utf8.decode(responseBuffer.asTypedList(bufferSize), allowMalformed: true).trim();
        if (errorText.isNotEmpty) {
          debugPrint('Error message from C++: $errorText');
        }
      } catch (e) {
        debugPrint('Could not read error message from buffer: $e');
      }
    }

    if (result > 0) {
      final responseText = utf8.decode(responseBuffer.asTypedList(result), allowMalformed: true).trim();
      try {
        final jsonResponse = jsonDecode(responseText) as Map<String, dynamic>;
        final success = jsonResponse['success'] as bool? ?? true;
        final text = (jsonResponse['text'] as String?) ??
                     (jsonResponse['response'] as String?) ??
                     responseText;
        final timeToFirstTokenMs = (jsonResponse['time_to_first_token_ms'] as num?)?.toDouble() ?? 0.0;
        final totalTimeMs = (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0;
        final tokensPerSecond = (jsonResponse['tokens_per_second'] as num?)?.toDouble() ?? 0.0;
        final confidence = (jsonResponse['confidence'] as num?)?.toDouble() ?? 0.0;
        final cloudHandoff = jsonResponse['cloud_handoff'] as bool? ?? false;

        List<TranscriptionSegment> segments = [];
        if (jsonResponse['segments'] != null) {
          final segmentsJson = jsonResponse['segments'] as List<dynamic>;
          segments = segmentsJson.map((seg) {
            final segMap = seg as Map<String, dynamic>;
            return TranscriptionSegment(
              start: (segMap['start'] as num?)?.toDouble() ?? 0.0,
              end: (segMap['end'] as num?)?.toDouble() ?? 0.0,
              text: segMap['text'] as String? ?? '',
            );
          }).toList();
        }

        return CactusTranscriptionResult(
          success: success,
          text: text.trim().replaceAll('<|startoftranscript|>', ''),
          timeToFirstTokenMs: timeToFirstTokenMs,
          totalTimeMs: totalTimeMs,
          tokensPerSecond: tokensPerSecond,
          confidence: confidence,
          cloudHandoff: cloudHandoff,
          segments: segments,
        );
      } catch (e) {
        debugPrint('Unable to parse the transcription response json: $e');
        return CactusTranscriptionResult(
          success: false,
          text: '',
        );
      }
    } else {
      return CactusTranscriptionResult(
        success: false,
        text: '',
        errorMessage: 'Error: transcription failed with code $result',
      );
    }
  } finally {
    _activeTokenCallback = null;
    calloc.free(responseBuffer);
    if (audioFilePathC != null) {
      calloc.free(audioFilePathC);
    }
    calloc.free(promptC);
    calloc.free(optionsJsonC);
    if (pcmBufferPtr != null) {
      calloc.free(pcmBufferPtr);
    }
  }
}

Future<PrefillResult> _prefillInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final messagesJson = params['messagesJson'] as String;
  final optionsJson = params['optionsJson'] as String;
  final toolsJson = params['toolsJson'] as String?;
  final bufferSize = params['bufferSize'] as int;
  final List<int>? pcmData = params['pcmData'] as List<int>?;

  final responseBuffer = calloc<Uint8>(bufferSize);
  final messagesJsonC = messagesJson.toNativeUtf8(allocator: calloc);
  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);
  final toolsJsonC = toolsJson?.toNativeUtf8(allocator: calloc);

  Pointer<Uint8>? pcmBufferPtr;
  if (pcmData != null) {
    final Uint8List pcmBytes = pcmData is Uint8List ? pcmData : Uint8List.fromList(pcmData);
    pcmBufferPtr = calloc<Uint8>(pcmBytes.length);
    final nativeList = pcmBufferPtr.asTypedList(pcmBytes.length);
    nativeList.setAll(0, pcmBytes);
  }

  try {
    final result = bindings.cactusPrefill(
      Pointer.fromAddress(handle),
      messagesJsonC,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      optionsJsonC,
      toolsJsonC ?? nullptr,
      pcmBufferPtr ?? nullptr,
      pcmData?.length ?? 0,
    );

    if (result > 0) {
      final responseText = utf8.decode(responseBuffer.asTypedList(result), allowMalformed: true).trim();
      try {
        final jsonResponse = jsonDecode(responseText) as Map<String, dynamic>;
        return PrefillResult(
          success: jsonResponse['success'] as bool? ?? true,
          prefillTokens: jsonResponse['prefill_tokens'] as int? ?? 0,
          prefillTps: (jsonResponse['prefill_tps'] as num?)?.toDouble() ?? 0.0,
          totalTimeMs: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
          ramUsageMb: (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse the prefill response json: $e');
        return PrefillResult(success: false, errorMessage: 'Unable to parse response');
      }
    } else {
      return PrefillResult(success: false, errorMessage: 'Prefill failed with code $result');
    }
  } finally {
    calloc.free(responseBuffer);
    calloc.free(messagesJsonC);
    calloc.free(optionsJsonC);
    if (toolsJsonC != null) {
      calloc.free(toolsJsonC);
    }
    if (pcmBufferPtr != null) {
      calloc.free(pcmBufferPtr);
    }
  }
}

Future<DetectLanguageResult> _detectLanguageInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final audioFilePath = params['audioFilePath'] as String?;
  final bufferSize = params['bufferSize'] as int;
  final optionsJson = params['optionsJson'] as String;
  final List<int>? pcmData = params['pcmData'] as List<int>?;

  final responseBuffer = calloc<Uint8>(bufferSize);
  final audioFilePathC = audioFilePath?.toNativeUtf8(allocator: calloc);
  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);

  Pointer<Uint8>? pcmBufferPtr;
  if (pcmData != null) {
    final Uint8List pcmBytes = pcmData is Uint8List ? pcmData : Uint8List.fromList(pcmData);
    pcmBufferPtr = calloc<Uint8>(pcmBytes.length);
    final nativeList = pcmBufferPtr.asTypedList(pcmBytes.length);
    nativeList.setAll(0, pcmBytes);
  }

  try {
    final result = bindings.cactusDetectLanguage(
      Pointer.fromAddress(handle),
      audioFilePathC ?? nullptr,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      optionsJsonC,
      pcmBufferPtr ?? nullptr,
      pcmData?.length ?? 0,
    );

    if (result > 0) {
      final responseText = utf8.decode(responseBuffer.asTypedList(result), allowMalformed: true).trim();
      try {
        final jsonResponse = jsonDecode(responseText) as Map<String, dynamic>;
        return DetectLanguageResult(
          language: jsonResponse['language'] as String? ?? '',
          confidence: (jsonResponse['confidence'] as num?)?.toDouble() ?? 0.0,
          languageToken: jsonResponse['language_token'] as String? ?? '',
        );
      } catch (e) {
        debugPrint('Unable to parse detect language response: $e');
        return DetectLanguageResult(language: '');
      }
    } else {
      return DetectLanguageResult(language: '');
    }
  } finally {
    calloc.free(responseBuffer);
    if (audioFilePathC != null) {
      calloc.free(audioFilePathC);
    }
    calloc.free(optionsJsonC);
    if (pcmBufferPtr != null) {
      calloc.free(pcmBufferPtr);
    }
  }
}

Future<VadResult> _vadInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final audioFilePath = params['audioFilePath'] as String?;
  final bufferSize = params['bufferSize'] as int;
  final optionsJson = params['optionsJson'] as String;
  final List<int>? pcmData = params['pcmData'] as List<int>?;

  final responseBuffer = calloc<Uint8>(bufferSize);
  final audioFilePathC = audioFilePath?.toNativeUtf8(allocator: calloc);
  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);

  Pointer<Uint8>? pcmBufferPtr;
  if (pcmData != null) {
    final Uint8List pcmBytes = pcmData is Uint8List ? pcmData : Uint8List.fromList(pcmData);
    pcmBufferPtr = calloc<Uint8>(pcmBytes.length);
    final nativeList = pcmBufferPtr.asTypedList(pcmBytes.length);
    nativeList.setAll(0, pcmBytes);
  }

  try {
    final result = bindings.cactusVad(
      Pointer.fromAddress(handle),
      audioFilePathC ?? nullptr,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      optionsJsonC,
      pcmBufferPtr ?? nullptr,
      pcmData?.length ?? 0,
    );

    if (result > 0) {
      final responseText = utf8.decode(responseBuffer.asTypedList(result), allowMalformed: true).trim();
      try {
        final jsonResponse = jsonDecode(responseText) as Map<String, dynamic>;
        List<VadSegment> segments = [];
        if (jsonResponse['segments'] != null) {
          final segmentsJson = jsonResponse['segments'] as List<dynamic>;
          segments = segmentsJson.map((seg) {
            final segMap = seg as Map<String, dynamic>;
            return VadSegment(
              start: segMap['start'] as int? ?? 0,
              end: segMap['end'] as int? ?? 0,
            );
          }).toList();
        }
        return VadResult(
          segments: segments,
          totalTimeMs: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse VAD response: $e');
        return VadResult();
      }
    } else {
      return VadResult();
    }
  } finally {
    calloc.free(responseBuffer);
    if (audioFilePathC != null) {
      calloc.free(audioFilePathC);
    }
    calloc.free(optionsJsonC);
    if (pcmBufferPtr != null) {
      calloc.free(pcmBufferPtr);
    }
  }
}

Future<DiarizeResult> _diarizeInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final audioFilePath = params['audioFilePath'] as String?;
  final bufferSize = params['bufferSize'] as int;
  final optionsJson = params['optionsJson'] as String;
  final List<int>? pcmData = params['pcmData'] as List<int>?;

  final responseBuffer = calloc<Uint8>(bufferSize);
  final audioFilePathC = audioFilePath?.toNativeUtf8(allocator: calloc);
  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);

  Pointer<Uint8>? pcmBufferPtr;
  if (pcmData != null) {
    final Uint8List pcmBytes = pcmData is Uint8List ? pcmData : Uint8List.fromList(pcmData);
    pcmBufferPtr = calloc<Uint8>(pcmBytes.length);
    final nativeList = pcmBufferPtr.asTypedList(pcmBytes.length);
    nativeList.setAll(0, pcmBytes);
  }

  try {
    final result = bindings.cactusDiarize(
      Pointer.fromAddress(handle),
      audioFilePathC ?? nullptr,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      optionsJsonC,
      pcmBufferPtr ?? nullptr,
      pcmData?.length ?? 0,
    );

    if (result > 0) {
      final responseText = utf8.decode(responseBuffer.asTypedList(result), allowMalformed: true).trim();
      try {
        final jsonResponse = jsonDecode(responseText) as Map<String, dynamic>;
        List<double> scores = [];
        if (jsonResponse['scores'] != null) {
          final scoresJson = jsonResponse['scores'] as List<dynamic>;
          scores = scoresJson.map((s) => (s as num).toDouble()).toList();
        }
        return DiarizeResult(
          numSpeakers: jsonResponse['num_speakers'] as int? ?? 0,
          scores: scores,
          totalTimeMs: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse diarize response: $e');
        return DiarizeResult();
      }
    } else {
      return DiarizeResult();
    }
  } finally {
    calloc.free(responseBuffer);
    if (audioFilePathC != null) {
      calloc.free(audioFilePathC);
    }
    calloc.free(optionsJsonC);
    if (pcmBufferPtr != null) {
      calloc.free(pcmBufferPtr);
    }
  }
}

Future<SpeakerEmbeddingResult> _embedSpeakerInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final audioFilePath = params['audioFilePath'] as String?;
  final bufferSize = params['bufferSize'] as int;
  final optionsJson = params['optionsJson'] as String;
  final List<int>? pcmData = params['pcmData'] as List<int>?;

  final responseBuffer = calloc<Uint8>(bufferSize);
  final audioFilePathC = audioFilePath?.toNativeUtf8(allocator: calloc);
  final optionsJsonC = optionsJson.toNativeUtf8(allocator: calloc);

  Pointer<Uint8>? pcmBufferPtr;
  if (pcmData != null) {
    final Uint8List pcmBytes = pcmData is Uint8List ? pcmData : Uint8List.fromList(pcmData);
    pcmBufferPtr = calloc<Uint8>(pcmBytes.length);
    final nativeList = pcmBufferPtr.asTypedList(pcmBytes.length);
    nativeList.setAll(0, pcmBytes);
  }

  try {
    final result = bindings.cactusEmbedSpeaker(
      Pointer.fromAddress(handle),
      audioFilePathC ?? nullptr,
      responseBuffer.cast<Utf8>(),
      bufferSize,
      optionsJsonC,
      pcmBufferPtr ?? nullptr,
      pcmData?.length ?? 0,
      nullptr,
      0,
    );

    if (result > 0) {
      final responseText = utf8.decode(responseBuffer.asTypedList(result), allowMalformed: true).trim();
      try {
        final jsonResponse = jsonDecode(responseText) as Map<String, dynamic>;
        List<double> embedding = [];
        if (jsonResponse['embedding'] != null) {
          final embeddingJson = jsonResponse['embedding'] as List<dynamic>;
          embedding = embeddingJson.map((e) => (e as num).toDouble()).toList();
        }
        return SpeakerEmbeddingResult(
          embedding: embedding,
          totalTimeMs: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse embed speaker response: $e');
        return SpeakerEmbeddingResult();
      }
    } else {
      return SpeakerEmbeddingResult();
    }
  } finally {
    calloc.free(responseBuffer);
    if (audioFilePathC != null) {
      calloc.free(audioFilePathC);
    }
    calloc.free(optionsJsonC);
    if (pcmBufferPtr != null) {
      calloc.free(pcmBufferPtr);
    }
  }
}

class CactusContext {
  static String _escapeJsonString(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  static Map<String, String?> _prepareCompletionJson(
    List<ChatMessage> messages,
    CactusCompletionParams params,
  ) {
    // Prepare messages JSON
    final messagesJsonBuffer = StringBuffer('[');
    for (int i = 0; i < messages.length; i++) {
      if (i > 0) messagesJsonBuffer.write(',');
      messagesJsonBuffer.write('{');
      messagesJsonBuffer.write('"role":"${messages[i].role}",');
      messagesJsonBuffer.write('"content":"${_escapeJsonString(messages[i].content)}"');
      if (messages[i].images.isNotEmpty) {
        messagesJsonBuffer.write(',"images":[');
        for (int j = 0; j < messages[i].images.length; j++) {
          if (j > 0) messagesJsonBuffer.write(',');
          messagesJsonBuffer.write('"${_escapeJsonString(messages[i].images[j])}"');
        }
        messagesJsonBuffer.write(']');
      }
      if (messages[i].audio.isNotEmpty) {
        messagesJsonBuffer.write(',"audio":[');
        for (int j = 0; j < messages[i].audio.length; j++) {
          if (j > 0) messagesJsonBuffer.write(',');
          messagesJsonBuffer.write('"${_escapeJsonString(messages[i].audio[j])}"');
        }
        messagesJsonBuffer.write(']');
      }
      messagesJsonBuffer.write('}');
    }
    messagesJsonBuffer.write(']');
    final messagesJson = messagesJsonBuffer.toString();

    // Prepare options JSON
    final optionsJsonBuffer = StringBuffer('{');
    params.temperature != null ? optionsJsonBuffer.write('"temperature":${params.temperature},') : null;
    params.topK != null ? optionsJsonBuffer.write('"top_k":${params.topK},') : null;
    params.topP != null ? optionsJsonBuffer.write('"top_p":${params.topP},') : null;
    params.forceTools != null ? optionsJsonBuffer.write('"force_tools":${params.forceTools},') : null;
    optionsJsonBuffer.write('"max_tokens":${params.maxTokens}');
    if (params.stopSequences.isNotEmpty) {
      optionsJsonBuffer.write(',"stop_sequences":[');
      for (int i = 0; i < params.stopSequences.length; i++) {
        if (i > 0) optionsJsonBuffer.write(',');
        optionsJsonBuffer.write('"${_escapeJsonString(params.stopSequences[i])}"');
      }
      optionsJsonBuffer.write(']');
    }
    optionsJsonBuffer.write('}');
    final optionsJson = optionsJsonBuffer.toString();

    // Prepare tools JSON if tools are provided
    String? toolsJson;
    if (params.tools != null && params.tools!.isNotEmpty) {
      toolsJson = params.tools!.toToolsJson();
    }

    return {
      'messagesJson': messagesJson,
      'optionsJson': optionsJson,
      'toolsJson': toolsJson,
    };
  }

  static Future<(int?, String)> initContext(String modelPath, int? contextSize) async {
    final isolateParams = {
      'modelPath': modelPath,
    };

    return await compute(_initContextInIsolate, isolateParams);
  }

  static void freeContext(int handle) {
    try {
      bindings.cactusDestroy(Pointer.fromAddress(handle));
      debugPrint('Context destroyed');
    } catch (e) {
      debugPrint('Error destroying context: $e');
    }
  }

  static void resetContext(int handle) {
    try {
      bindings.cactusReset(Pointer.fromAddress(handle));
      debugPrint('Context reset - cache cleared');
    } catch (e) {
      debugPrint('Error resetting context: $e');
    }
  }

  static Future<CactusCompletionResult> completion(
    int handle,
    List<ChatMessage> messages,
    CactusCompletionParams params,
    int quantization
  ) async {
    final jsonData = _prepareCompletionJson(messages, params);

    return await compute(_completionInIsolate, {
      'handle': handle,
      'messagesJson': jsonData['messagesJson']!,
      'optionsJson': jsonData['optionsJson']!,
      'toolsJson': jsonData['toolsJson'],
      'bufferSize': max(params.maxTokens * quantization, 2048),
      'hasCallback': false,
      'replyPort': null,
    });
  }

  static CactusStreamedCompletionResult completionStream(
    int handle,
    List<ChatMessage> messages,
    CactusCompletionParams params,
    int quantization
  ) {
    final jsonData = _prepareCompletionJson(messages, params);

    final controller = StreamController<String>();
    final resultCompleter = Completer<CactusCompletionResult>();
    final replyPort = ReceivePort();

    late StreamSubscription subscription;
    subscription = replyPort.listen((message) {
      if (message is Map) {
        final type = message['type'] as String;
        if (type == 'token') {
          final token = message['data'] as String;
          controller.add(token);
        } else if (type == 'result') {
          final result = message['data'] as CactusCompletionResult;
          resultCompleter.complete(result);
          controller.close();
          subscription.cancel();
          replyPort.close();
        } else if (type == 'error') {
          final error = message['data'];
          if (error is CactusCompletionResult) {
            resultCompleter.complete(error);
          } else {
            resultCompleter.completeError(error.toString());
          }
          controller.addError(error);
          controller.close();
          subscription.cancel();
          replyPort.close();
        }
      }
    });

    Isolate.spawn(_isolateCompletionEntry, {
      'handle': handle,
      'messagesJson': jsonData['messagesJson']!,
      'optionsJson': jsonData['optionsJson']!,
      'toolsJson': jsonData['toolsJson'],
      'bufferSize': max(params.maxTokens * quantization, 2048),
      'hasCallback': true,
      'replyPort': replyPort.sendPort,
    });

    return CactusStreamedCompletionResult(
      stream: controller.stream,
      result: resultCompleter.future,
    );
  }

  static Future<CactusEmbeddingResult> generateEmbedding(int handle, String text, int quantization) async {
    return await compute(_generateEmbeddingInIsolate, {
      'handle': handle,
      'text': text,
      'bufferSize': max(text.length * quantization, 1024),
    });
  }

  static Future<PrefillResult> prefill(
    int handle,
    List<ChatMessage> messages,
    CactusCompletionParams params, {
    List<int>? pcmData,
    int quantization = 8,
  }) async {
    final jsonData = _prepareCompletionJson(messages, params);
    return await compute(_prefillInIsolate, {
      'handle': handle,
      'messagesJson': jsonData['messagesJson']!,
      'optionsJson': jsonData['optionsJson']!,
      'toolsJson': jsonData['toolsJson'],
      'bufferSize': max(params.maxTokens * quantization, 2048),
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  static Future<DetectLanguageResult> detectLanguage(
    int handle, {
    String? audioFilePath,
    List<int>? pcmData,
    int bufferSize = 4096,
  }) async {
    return await compute(_detectLanguageInIsolate, {
      'handle': handle,
      'audioFilePath': audioFilePath,
      'optionsJson': '{}',
      'bufferSize': bufferSize,
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  static Future<VadResult> vad(
    int handle, {
    String? audioFilePath,
    List<int>? pcmData,
    int bufferSize = 4096,
  }) async {
    return await compute(_vadInIsolate, {
      'handle': handle,
      'audioFilePath': audioFilePath,
      'optionsJson': '{}',
      'bufferSize': bufferSize,
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  static Future<DiarizeResult> diarize(
    int handle, {
    String? audioFilePath,
    List<int>? pcmData,
    int bufferSize = 4096,
  }) async {
    return await compute(_diarizeInIsolate, {
      'handle': handle,
      'audioFilePath': audioFilePath,
      'optionsJson': '{}',
      'bufferSize': bufferSize,
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  static Future<SpeakerEmbeddingResult> embedSpeaker(
    int handle, {
    String? audioFilePath,
    List<int>? pcmData,
    int bufferSize = 4096,
  }) async {
    return await compute(_embedSpeakerInIsolate, {
      'handle': handle,
      'audioFilePath': audioFilePath,
      'optionsJson': '{}',
      'bufferSize': bufferSize,
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  static Future<CactusTranscriptionResult> transcribe(
    int handle,
    String prompt, {
    String? audioFilePath,
    List<int>? pcmData,
    CactusTranscriptionParams? params,
  }) async {
    final transcriptionParams = params ?? CactusTranscriptionParams();
    final optionsJson = '{"max_tokens":${transcriptionParams.maxTokens}}';

    return await compute(_transcribeInIsolate, {
      'handle': handle,
      'audioFilePath': audioFilePath,
      'prompt': prompt,
      'optionsJson': optionsJson,
      'bufferSize': transcriptionParams.maxTokens * 8,
      'hasCallback': false,
      'replyPort': null,
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  static CactusStreamedTranscriptionResult transcribeStream(
    int handle,
    String prompt, {
    String? audioFilePath,
    List<int>? pcmData,
    CactusTranscriptionParams? params,
  }) {
    final transcriptionParams = params ?? CactusTranscriptionParams();
    final optionsJson = '{"max_tokens":${transcriptionParams.maxTokens}}';

    final controller = StreamController<String>();
    final resultCompleter = Completer<CactusTranscriptionResult>();
    final replyPort = ReceivePort();

    late StreamSubscription subscription;
    subscription = replyPort.listen((message) {
      if (message is Map) {
        final type = message['type'] as String;
        if (type == 'token') {
          final token = message['data'] as String;
          if(!transcriptionParams.stopSequences.contains(token)) {
            controller.add(token);
          }
        } else if (type == 'result') {
          final result = message['data'] as CactusTranscriptionResult;
          resultCompleter.complete(result);
          controller.close();
          subscription.cancel();
          replyPort.close();
        } else if (type == 'error') {
          final error = message['data'];
          if (error is CactusTranscriptionResult) {
            resultCompleter.complete(error);
          } else {
            resultCompleter.completeError(error.toString());
          }
          controller.addError(error);
          controller.close();
          subscription.cancel();
          replyPort.close();
        }
      }
    });

    Isolate.spawn(_isolateTranscriptionEntry, {
      'handle': handle,
      'audioFilePath': audioFilePath,
      'prompt': prompt,
      'optionsJson': optionsJson,
      'bufferSize': transcriptionParams.maxTokens * 8,
      'hasCallback': true,
      'replyPort': replyPort.sendPort,
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });

    return CactusStreamedTranscriptionResult(
      stream: controller.stream,
      result: resultCompleter.future,
    );
  }

  static Future<void> _isolateCompletionEntry(Map<String, dynamic> params) async {
    final replyPort = params['replyPort'] as SendPort;
    try {
      final result = await _completionInIsolate(params);
      if (result.success) {
        replyPort.send({'type': 'result', 'data': result});
      } else {
        replyPort.send({'type': 'error', 'data': result});
      }
    } catch (e) {
      replyPort.send({'type': 'error', 'data': e.toString()});
    }
  }

  static Future<void> _isolateTranscriptionEntry(Map<String, dynamic> params) async {
    final replyPort = params['replyPort'] as SendPort;
    try {
      final result = await _transcribeInIsolate(params);
      if (result.success) {
        replyPort.send({'type': 'result', 'data': result});
      } else {
        replyPort.send({'type': 'error', 'data': result});
      }
    } catch (e) {
      replyPort.send({'type': 'error', 'data': e.toString()});
    }
  }
}