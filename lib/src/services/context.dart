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

CactusTokenCallback? _activeTokenCallback;

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
  final corpusDir = params['corpusDir'] as String?;
  final cacheIndex = params['cacheIndex'] as bool? ?? false;

  try {
    debugPrint('Initializing context with model: $modelPath');
    final modelPathC = modelPath.toNativeUtf8(allocator: calloc);
    final corpusDirC = corpusDir != null ? corpusDir.toNativeUtf8(allocator: calloc) : nullptr;
    try {
      final handle = bindings.cactusInit(modelPathC, corpusDirC, cacheIndex);
      if (handle != nullptr) {
        return (handle.address, 'Context initialized successfully');
      } else {
        return (null, 'Failed to initialize context');
      }
    } finally {
      calloc.free(modelPathC);
      if (corpusDirC != nullptr) {
        calloc.free(corpusDirC);
      }
    }
  } catch (e) {
    return (null, 'Exception during context initialization: $e');
  }
}

Future<CactusLMCompleteResult> _completionInIsolate(Map<String, dynamic> params) async {
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
        final prefillTokens = jsonResponse['prefill_tokens'] as int? ?? 0;
        final decodeTokens = jsonResponse['decode_tokens'] as int? ?? 0;
        final totalTokens = jsonResponse['total_tokens'] as int? ?? 0;
        final confidence = (jsonResponse['confidence'] as num?)?.toDouble() ?? 0.0;
        final cloudHandoff = jsonResponse['cloud_handoff'] as bool? ?? false;
        final thinking = jsonResponse['thinking'] as String?;
        final prefillTps = (jsonResponse['prefill_tps'] as num?)?.toDouble() ?? 0.0;
        final decodeTps = (jsonResponse['decode_tps'] as num?)?.toDouble() ?? 0.0;
        final ramUsageMb = (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0;
        
        List<FunctionCall> functionCalls = [];
        if (jsonResponse['function_calls'] != null) {
          final functionCallsJson = jsonResponse['function_calls'] as List<dynamic>;
          functionCalls = functionCallsJson
              .map((fcJson) {
                final fcMap = fcJson as Map<String, dynamic>;
                return FunctionCall(
                  name: fcMap['name'] as String,
                  arguments: fcMap['arguments'] is Map<String, dynamic>
                      ? fcMap['arguments'] as Map<String, dynamic>
                      : Map<String, dynamic>.from(fcMap['arguments'] as Map),
                );
              })
              .toList();
        }

        return CactusLMCompleteResult(
          success: success,
          response: response,
          timeToFirstTokenMs: timeToFirstTokenMs,
          totalTimeMs: totalTimeMs,
          prefillTokens: prefillTokens,
          prefillTps: prefillTps,
          decodeTokens: decodeTokens,
          decodeTps: decodeTps,
          totalTokens: totalTokens,
          functionCalls: functionCalls.isNotEmpty ? functionCalls : null,
          confidence: confidence,
          cloudHandoff: cloudHandoff,
          thinking: thinking,
          ramUsageMb: ramUsageMb,
        );
      } catch (e) {
        debugPrint('Unable to parse the response json: $e');
        return CactusLMCompleteResult(
          success: false,
          response: 'Error: Unable to parse the response',
          timeToFirstTokenMs: 0.0,
          totalTimeMs: 0.0,
          prefillTokens: 0,
          prefillTps: 0.0,
          decodeTokens: 0,
          decodeTps: 0.0,
          totalTokens: 0,
          confidence: 0.0,
          cloudHandoff: false,
          ramUsageMb: 0.0,
        );
      }
    } else {
      return CactusLMCompleteResult(
        success: false,
        response: 'Error: completion failed with code $result',
        timeToFirstTokenMs: 0.0,
        totalTimeMs: 0.0,
        prefillTokens: 0,
        prefillTps: 0.0,
        decodeTokens: 0,
        decodeTps: 0.0,
        totalTokens: 0,
        confidence: 0.0,
        cloudHandoff: false,
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

Future<CactusLMEmbedResult> _generateEmbeddingInIsolate(Map<String, dynamic> params) async {
  final handle = params['handle'] as int;
  final text = params['text'] as String;
  final bufferSize = params['bufferSize'] as int;

  final textC = text.toNativeUtf8(allocator: calloc);
  final embeddingDimPtr = calloc<IntPtr>();
  final embeddingsBuffer = calloc<Float>(bufferSize);

  try {
    debugPrint('Generating embedding for text: ${text.length > 50 ? "${text.substring(0, 50)}..." : text}');

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
        return CactusLMEmbedResult(embedding: []);
      }

      final embeddings = <double>[];
      for (int i = 0; i < actualEmbeddingDim; i++) {
        embeddings.add(embeddingsBuffer[i]);
      }

      debugPrint('Successfully extracted ${embeddings.length} embedding values');

      return CactusLMEmbedResult(embedding: embeddings);
    } else {
      return CactusLMEmbedResult(embedding: []);
    }
  } catch (e) {
    debugPrint('Exception during embedding generation: $e');
    return CactusLMEmbedResult(embedding: []);
  } finally {
    calloc.free(textC);
    calloc.free(embeddingDimPtr);
    calloc.free(embeddingsBuffer);
  }
}

Future<CactusSTTTranscribeResult> _transcribeInIsolate(Map<String, dynamic> params) async {
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
    return CactusSTTTranscribeResult(
      success: false,
      response: 'Either audio file path or PCM buffer must be provided',
      timeToFirstTokenMs: 0.0,
      totalTimeMs: 0.0,
      prefillTokens: 0,
      prefillTps: 0.0,
      decodeTokens: 0,
      decodeTps: 0.0,
      totalTokens: 0,
    );
  }

  if (audioFilePath != null) {
    final audioFile = File(audioFilePath);
    if (!audioFile.existsSync()) {
      debugPrint('ERROR: Audio file does not exist at path: $audioFilePath');
      return CactusSTTTranscribeResult(
        success: false,
        response: 'Audio file not found: $audioFilePath',
        timeToFirstTokenMs: 0.0,
        totalTimeMs: 0.0,
        prefillTokens: 0,
        prefillTps: 0.0,
        decodeTokens: 0,
        decodeTps: 0.0,
        totalTokens: 0,
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
        final response = (jsonResponse['response'] as String?) ??
                     (jsonResponse['text'] as String?) ??
                     responseText;
        final timeToFirstTokenMs = (jsonResponse['time_to_first_token_ms'] as num?)?.toDouble() ?? 0.0;
        final totalTimeMs = (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0;
        final confidence = (jsonResponse['confidence'] as num?)?.toDouble() ?? 0.0;
        final cloudHandoff = jsonResponse['cloud_handoff'] as bool? ?? false;
        final prefillTokens = jsonResponse['prefill_tokens'] as int? ?? 0;
        final prefillTps = (jsonResponse['prefill_tps'] as num?)?.toDouble() ?? 0.0;
        final decodeTokens = jsonResponse['decode_tokens'] as int? ?? 0;
        final decodeTps = (jsonResponse['decode_tps'] as num?)?.toDouble() ?? 0.0;
        final totalTokens = jsonResponse['total_tokens'] as int? ?? 0;
        final ramUsageMb = (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0;

        return CactusSTTTranscribeResult(
          success: success,
          response: response.trim().replaceAll('<|startoftranscript|>', ''),
          timeToFirstTokenMs: timeToFirstTokenMs,
          totalTimeMs: totalTimeMs,
          confidence: confidence,
          cloudHandoff: cloudHandoff,
          prefillTokens: prefillTokens,
          prefillTps: prefillTps,
          decodeTokens: decodeTokens,
          decodeTps: decodeTps,
          totalTokens: totalTokens,
          ramUsageMb: ramUsageMb,
        );
      } catch (e) {
        debugPrint('Unable to parse the transcription response json: $e');
        return CactusSTTTranscribeResult(
          success: false,
          response: '',
          timeToFirstTokenMs: 0.0,
          totalTimeMs: 0.0,
          prefillTokens: 0,
          prefillTps: 0.0,
          decodeTokens: 0,
          decodeTps: 0.0,
          totalTokens: 0,
        );
      }
    } else {
      return CactusSTTTranscribeResult(
        success: false,
        response: 'Error: transcription failed with code $result',
        timeToFirstTokenMs: 0.0,
        totalTimeMs: 0.0,
        prefillTokens: 0,
        prefillTps: 0.0,
        decodeTokens: 0,
        decodeTps: 0.0,
        totalTokens: 0,
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

Future<CactusLMPrefillResult> _prefillInIsolate(Map<String, dynamic> params) async {
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
        return CactusLMPrefillResult(
          success: jsonResponse['success'] as bool? ?? true,
          prefillTokens: jsonResponse['prefill_tokens'] as int? ?? 0,
          prefillTps: (jsonResponse['prefill_tps'] as num?)?.toDouble() ?? 0.0,
          totalTimeMs: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
          ramUsageMb: (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse the prefill response json: $e');
        return CactusLMPrefillResult(success: false, error: 'Unable to parse response');
      }
    } else {
      return CactusLMPrefillResult(success: false, error: 'Prefill failed with code $result');
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

Future<CactusSTTDetectLanguageResult> _detectLanguageInIsolate(Map<String, dynamic> params) async {
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
        return CactusSTTDetectLanguageResult(
          language: jsonResponse['language'] as String? ?? '',
          confidence: (jsonResponse['confidence'] as num?)?.toDouble(),
        );
      } catch (e) {
        debugPrint('Unable to parse detect language response: $e');
        return CactusSTTDetectLanguageResult(language: '');
      }
    } else {
      return CactusSTTDetectLanguageResult(language: '');
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

Future<CactusAudioVADResult> _vadInIsolate(Map<String, dynamic> params) async {
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
        List<CactusAudioVADSegment> segments = [];
        if (jsonResponse['segments'] != null) {
          final segmentsJson = jsonResponse['segments'] as List<dynamic>;
          segments = segmentsJson.map((seg) {
            final segMap = seg as Map<String, dynamic>;
            return CactusAudioVADSegment(
              start: segMap['start'] as int? ?? 0,
              end: segMap['end'] as int? ?? 0,
            );
          }).toList();
        }
        return CactusAudioVADResult(
          segments: segments,
          totalTime: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
          ramUsage: (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse VAD response: $e');
        return CactusAudioVADResult(segments: [], totalTime: 0.0, ramUsage: 0.0);
      }
    } else {
      return CactusAudioVADResult(segments: [], totalTime: 0.0, ramUsage: 0.0);
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

Future<CactusAudioDiarizeResult> _diarizeInIsolate(Map<String, dynamic> params) async {
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
        return CactusAudioDiarizeResult(
          success: jsonResponse['success'] as bool? ?? true,
          numSpeakers: jsonResponse['num_speakers'] as int? ?? 0,
          scores: scores,
          totalTimeMs: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
          ramUsageMb: (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse diarize response: $e');
        return CactusAudioDiarizeResult(success: false, error: 'Unable to parse response');
      }
    } else {
      return CactusAudioDiarizeResult(success: false, error: 'Diarize failed with code $result');
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

Future<CactusAudioEmbedSpeakerResult> _embedSpeakerInIsolate(Map<String, dynamic> params) async {
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
        return CactusAudioEmbedSpeakerResult(
          success: jsonResponse['success'] as bool? ?? true,
          embedding: embedding,
          totalTimeMs: (jsonResponse['total_time_ms'] as num?)?.toDouble() ?? 0.0,
          ramUsageMb: (jsonResponse['ram_usage_mb'] as num?)?.toDouble() ?? 0.0,
        );
      } catch (e) {
        debugPrint('Unable to parse embed speaker response: $e');
        return CactusAudioEmbedSpeakerResult(success: false, error: 'Unable to parse response');
      }
    } else {
      return CactusAudioEmbedSpeakerResult(success: false, error: 'Embed speaker failed');
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
  static Map<String, String?> _prepareCompletionJson(
    List<CactusLMMessage> messages,
    CactusLMCompleteOptions params, {
    List<CactusTool>? tools,
  }) {
    final messagesJson = jsonEncode(messages.map((m) => m.toJson()).toList());

    final optionsMap = <String, dynamic>{};
    if (params.temperature != null) optionsMap['temperature'] = params.temperature;
    if (params.topK != null) optionsMap['top_k'] = params.topK;
    if (params.topP != null) optionsMap['top_p'] = params.topP;
    optionsMap['max_tokens'] = params.maxTokens;
    if (params.stopSequences.isNotEmpty) optionsMap['stop_sequences'] = params.stopSequences;
    if (params.forceTools != null) optionsMap['force_tools'] = params.forceTools;
    if (params.telemetryEnabled != null) optionsMap['telemetry_enabled'] = params.telemetryEnabled;
    if (params.confidenceThreshold != null) optionsMap['confidence_threshold'] = params.confidenceThreshold;
    if (params.includeStopSequences != null) optionsMap['include_stop_sequences'] = params.includeStopSequences;
    if (params.enableThinking != null) optionsMap['enable_thinking'] = params.enableThinking;
    final optionsJson = jsonEncode(optionsMap);

    String? toolsJson;
    if (tools != null && tools.isNotEmpty) {
      toolsJson = tools.toToolsJson();
    }

    return {
      'messagesJson': messagesJson,
      'optionsJson': optionsJson,
      'toolsJson': toolsJson,
    };
  }

  static String _buildTranscriptionOptionsJson(CactusSTTTranscribeOptions params) {
    final optionsMap = <String, dynamic>{};
    if (params.temperature != null) optionsMap['temperature'] = params.temperature;
    if (params.topK != null) optionsMap['top_k'] = params.topK;
    if (params.topP != null) optionsMap['top_p'] = params.topP;
    optionsMap['max_tokens'] = params.maxTokens;
    if (params.stopSequences.isNotEmpty) optionsMap['stop_sequences'] = params.stopSequences;
    if (params.useVad != null) optionsMap['use_vad'] = params.useVad;
    if (params.telemetryEnabled != null) optionsMap['telemetry_enabled'] = params.telemetryEnabled;
    if (params.confidenceThreshold != null) optionsMap['confidence_threshold'] = params.confidenceThreshold;
    if (params.cloudHandoffThreshold != null) optionsMap['cloud_handoff_threshold'] = params.cloudHandoffThreshold;
    if (params.includeStopSequences != null) optionsMap['include_stop_sequences'] = params.includeStopSequences;
    return jsonEncode(optionsMap);
  }

  static Future<(int?, String)> initContext(String modelPath, int? contextSize, {String? corpusDir, bool cacheIndex = false}) async {
    final isolateParams = {
      'modelPath': modelPath,
      'corpusDir': corpusDir,
      'cacheIndex': cacheIndex,
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

  static Future<CactusLMCompleteResult> completion(
    int handle,
    List<CactusLMMessage> messages,
    CactusLMCompleteOptions params,
    int quantization, {
    List<CactusTool>? tools,
  }) async {
    final jsonData = _prepareCompletionJson(messages, params, tools: tools);

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

  static Future<CactusLMCompleteResult> completionStream(
    int handle,
    List<CactusLMMessage> messages,
    CactusLMCompleteOptions params,
    int quantization, {
    List<CactusTool>? tools,
    void Function(String token)? onToken,
  }) async {
    final jsonData = _prepareCompletionJson(messages, params, tools: tools);

    final resultCompleter = Completer<CactusLMCompleteResult>();
    final replyPort = ReceivePort();

    late StreamSubscription subscription;
    subscription = replyPort.listen((message) {
      if (message is Map) {
        final type = message['type'] as String;
        if (type == 'token') {
          final token = message['data'] as String;
          onToken?.call(token);
        } else if (type == 'result') {
          final result = message['data'] as CactusLMCompleteResult;
          resultCompleter.complete(result);
          subscription.cancel();
          replyPort.close();
        } else if (type == 'error') {
          final error = message['data'];
          if (error is CactusLMCompleteResult) {
            resultCompleter.complete(error);
          } else {
            resultCompleter.completeError(error.toString());
          }
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

    return resultCompleter.future;
  }

  static Future<CactusLMEmbedResult> generateEmbedding(int handle, String text, int quantization) async {
    return await compute(_generateEmbeddingInIsolate, {
      'handle': handle,
      'text': text,
      'bufferSize': max(text.length * quantization, 1024),
    });
  }

  static Future<CactusLMPrefillResult> prefill(
    int handle,
    List<CactusLMMessage> messages,
    CactusLMCompleteOptions params, {
    List<CactusTool>? tools,
    List<int>? pcmData,
    int quantization = 8,
  }) async {
    final jsonData = _prepareCompletionJson(messages, params, tools: tools);
    return await compute(_prefillInIsolate, {
      'handle': handle,
      'messagesJson': jsonData['messagesJson']!,
      'optionsJson': jsonData['optionsJson']!,
      'toolsJson': jsonData['toolsJson'],
      'bufferSize': max(params.maxTokens * quantization, 2048),
      'pcmData': pcmData != null ? Uint8List.fromList(pcmData) : null,
    });
  }

  static Future<CactusSTTDetectLanguageResult> detectLanguage(
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

  static Future<CactusAudioVADResult> vad(
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

  static Future<CactusAudioDiarizeResult> diarize(
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

  static Future<CactusAudioEmbedSpeakerResult> embedSpeaker(
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

  static Future<CactusSTTTranscribeResult> transcribe(
    int handle,
    String prompt, {
    String? audioFilePath,
    List<int>? pcmData,
    CactusSTTTranscribeOptions? params,
  }) async {
    final transcriptionParams = params ?? const CactusSTTTranscribeOptions();
    final optionsJson = _buildTranscriptionOptionsJson(transcriptionParams);

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

  static Future<CactusSTTTranscribeResult> transcribeStream(
    int handle,
    String prompt, {
    String? audioFilePath,
    List<int>? pcmData,
    CactusSTTTranscribeOptions? params,
    void Function(String token)? onToken,
  }) async {
    final transcriptionParams = params ?? const CactusSTTTranscribeOptions();
    final optionsJson = _buildTranscriptionOptionsJson(transcriptionParams);

    final resultCompleter = Completer<CactusSTTTranscribeResult>();
    final replyPort = ReceivePort();

    late StreamSubscription subscription;
    subscription = replyPort.listen((message) {
      if (message is Map) {
        final type = message['type'] as String;
        if (type == 'token') {
          final token = message['data'] as String;
          onToken?.call(token);
        } else if (type == 'result') {
          final result = message['data'] as CactusSTTTranscribeResult;
          resultCompleter.complete(result);
          subscription.cancel();
          replyPort.close();
        } else if (type == 'error') {
          final error = message['data'];
          if (error is CactusSTTTranscribeResult) {
            resultCompleter.complete(error);
          } else {
            resultCompleter.completeError(error.toString());
          }
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

    return resultCompleter.future;
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
