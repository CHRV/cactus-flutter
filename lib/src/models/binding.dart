import 'dart:ffi';
import 'package:ffi/ffi.dart';

final class CactusModelOpaque extends Opaque {}
typedef CactusModel = Pointer<CactusModelOpaque>;

final class CactusIndexOpaque extends Opaque {}
typedef CactusIndex = Pointer<CactusIndexOpaque>;

final class CactusStreamOpaque extends Opaque {}
typedef CactusStream = Pointer<CactusStreamOpaque>;

typedef CactusTokenCallbackNative = Void Function(
    Pointer<Utf8> token, Uint32 tokenId, Pointer<Void> userData);
typedef CactusTokenCallbackDart = void Function(
    Pointer<Utf8> token, int tokenId, Pointer<Void> userData);

typedef CactusLogCallbackNative = Void Function(
    Int32 level, Pointer<Utf8> component, Pointer<Utf8> message, Pointer<Void> userData);

typedef CactusInitNative = CactusModel Function(
    Pointer<Utf8> modelPath, Pointer<Utf8> corpusDir, Bool cacheIndex);
typedef CactusInitDart = CactusModel Function(
    Pointer<Utf8> modelPath, Pointer<Utf8> corpusDir, bool cacheIndex);

typedef CactusDestroyNative = Void Function(CactusModel model);
typedef CactusDestroyDart = void Function(CactusModel model);

typedef CactusResetNative = Void Function(CactusModel model);
typedef CactusResetDart = void Function(CactusModel model);

typedef CactusStopNative = Void Function(CactusModel model);
typedef CactusStopDart = void Function(CactusModel model);

typedef CactusGetLastErrorNative = Pointer<Utf8> Function();
typedef CactusGetLastErrorDart = Pointer<Utf8> Function();

typedef CactusCompleteNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> messagesJson,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Utf8> toolsJson,
    Pointer<NativeFunction<CactusTokenCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef CactusCompleteDart = int Function(
    CactusModel model,
    Pointer<Utf8> messagesJson,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Utf8> toolsJson,
    Pointer<NativeFunction<CactusTokenCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef CactusPrefillNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> messagesJson,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Utf8> toolsJson,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef CactusPrefillDart = int Function(
    CactusModel model,
    Pointer<Utf8> messagesJson,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Utf8> toolsJson,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef CactusTokenizeNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> text,
    Pointer<Uint32> tokenBuffer,
    IntPtr tokenBufferLen,
    Pointer<IntPtr> outTokenLen);
typedef CactusTokenizeDart = int Function(
    CactusModel model,
    Pointer<Utf8> text,
    Pointer<Uint32> tokenBuffer,
    int tokenBufferLen,
    Pointer<IntPtr> outTokenLen);

typedef CactusScoreWindowNative = Int32 Function(
    CactusModel model,
    Pointer<Uint32> tokens,
    IntPtr tokenLen,
    IntPtr start,
    IntPtr end,
    IntPtr context,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize);
typedef CactusScoreWindowDart = int Function(
    CactusModel model,
    Pointer<Uint32> tokens,
    int tokenLen,
    int start,
    int end,
    int context,
    Pointer<Utf8> responseBuffer,
    int bufferSize);

typedef CactusTranscribeNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> prompt,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<NativeFunction<CactusTokenCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef CactusTranscribeDart = int Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> prompt,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<NativeFunction<CactusTokenCallbackNative>> callback,
    Pointer<Void> userData,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef CactusDetectLanguageNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef CactusDetectLanguageDart = int Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef CactusVadNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef CactusVadDart = int Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef CactusDiarizeNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize);
typedef CactusDiarizeDart = int Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize);

typedef CactusEmbedSpeakerNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize,
    Pointer<Float> maskWeights,
    IntPtr maskNumFrames);
typedef CactusEmbedSpeakerDart = int Function(
    CactusModel model,
    Pointer<Utf8> audioFilePath,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    Pointer<Utf8> optionsJson,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize,
    Pointer<Float> maskWeights,
    int maskNumFrames);

typedef CactusStreamTranscribeStartNative = CactusStream Function(
    CactusModel model, Pointer<Utf8> optionsJson);
typedef CactusStreamTranscribeStartDart = CactusStream Function(
    CactusModel model, Pointer<Utf8> optionsJson);

typedef CactusStreamTranscribeProcessNative = Int32 Function(
    CactusStream stream,
    Pointer<Uint8> pcmBuffer,
    IntPtr pcmBufferSize,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize);
typedef CactusStreamTranscribeProcessDart = int Function(
    CactusStream stream,
    Pointer<Uint8> pcmBuffer,
    int pcmBufferSize,
    Pointer<Utf8> responseBuffer,
    int bufferSize);

typedef CactusStreamTranscribeStopNative = Int32 Function(
    CactusStream stream, Pointer<Utf8> responseBuffer, IntPtr bufferSize);
typedef CactusStreamTranscribeStopDart = int Function(
    CactusStream stream, Pointer<Utf8> responseBuffer, int bufferSize);

typedef CactusEmbedNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> text,
    Pointer<Float> embeddingsBuffer,
    IntPtr bufferSize,
    Pointer<IntPtr> embeddingDim,
    Bool normalize);
typedef CactusEmbedDart = int Function(
    CactusModel model,
    Pointer<Utf8> text,
    Pointer<Float> embeddingsBuffer,
    int bufferSize,
    Pointer<IntPtr> embeddingDim,
    bool normalize);

typedef CactusImageEmbedNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> imagePath,
    Pointer<Float> embeddingsBuffer,
    IntPtr bufferSize,
    Pointer<IntPtr> embeddingDim);
typedef CactusImageEmbedDart = int Function(
    CactusModel model,
    Pointer<Utf8> imagePath,
    Pointer<Float> embeddingsBuffer,
    int bufferSize,
    Pointer<IntPtr> embeddingDim);

typedef CactusAudioEmbedNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> audioPath,
    Pointer<Float> embeddingsBuffer,
    IntPtr bufferSize,
    Pointer<IntPtr> embeddingDim);
typedef CactusAudioEmbedDart = int Function(
    CactusModel model,
    Pointer<Utf8> audioPath,
    Pointer<Float> embeddingsBuffer,
    int bufferSize,
    Pointer<IntPtr> embeddingDim);

typedef CactusRagQueryNative = Int32 Function(
    CactusModel model,
    Pointer<Utf8> query,
    Pointer<Utf8> responseBuffer,
    IntPtr bufferSize,
    IntPtr topK);
typedef CactusRagQueryDart = int Function(
    CactusModel model,
    Pointer<Utf8> query,
    Pointer<Utf8> responseBuffer,
    int bufferSize,
    int topK);

typedef CactusIndexInitNative = CactusIndex Function(
    Pointer<Utf8> indexDir, IntPtr embeddingDim);
typedef CactusIndexInitDart = CactusIndex Function(
    Pointer<Utf8> indexDir, int embeddingDim);

typedef CactusIndexAddNative = Int32 Function(
    CactusIndex index,
    Pointer<Int32> ids,
    Pointer<Pointer<Utf8>> documents,
    Pointer<Pointer<Utf8>> metadatas,
    Pointer<Pointer<Float>> embeddings,
    IntPtr count,
    IntPtr embeddingDim);
typedef CactusIndexAddDart = int Function(
    CactusIndex index,
    Pointer<Int32> ids,
    Pointer<Pointer<Utf8>> documents,
    Pointer<Pointer<Utf8>> metadatas,
    Pointer<Pointer<Float>> embeddings,
    int count,
    int embeddingDim);

typedef CactusIndexDeleteNative = Int32 Function(
    CactusIndex index, Pointer<Int32> ids, IntPtr idsCount);
typedef CactusIndexDeleteDart = int Function(
    CactusIndex index, Pointer<Int32> ids, int idsCount);

typedef CactusIndexGetNative = Int32 Function(
    CactusIndex index,
    Pointer<Int32> ids,
    IntPtr idsCount,
    Pointer<Pointer<Utf8>> documentBuffers,
    Pointer<IntPtr> documentBufferSizes,
    Pointer<Pointer<Utf8>> metadataBuffers,
    Pointer<IntPtr> metadataBufferSizes,
    Pointer<Pointer<Float>> embeddingBuffers,
    Pointer<IntPtr> embeddingBufferSizes);
typedef CactusIndexGetDart = int Function(
    CactusIndex index,
    Pointer<Int32> ids,
    int idsCount,
    Pointer<Pointer<Utf8>> documentBuffers,
    Pointer<IntPtr> documentBufferSizes,
    Pointer<Pointer<Utf8>> metadataBuffers,
    Pointer<IntPtr> metadataBufferSizes,
    Pointer<Pointer<Float>> embeddingBuffers,
    Pointer<IntPtr> embeddingBufferSizes);

typedef CactusIndexQueryNative = Int32 Function(
    CactusIndex index,
    Pointer<Pointer<Float>> embeddings,
    IntPtr embeddingsCount,
    IntPtr embeddingDim,
    Pointer<Utf8> optionsJson,
    Pointer<Pointer<Int32>> idBuffers,
    Pointer<IntPtr> idBufferSizes,
    Pointer<Pointer<Float>> scoreBuffers,
    Pointer<IntPtr> scoreBufferSizes);
typedef CactusIndexQueryDart = int Function(
    CactusIndex index,
    Pointer<Pointer<Float>> embeddings,
    int embeddingsCount,
    int embeddingDim,
    Pointer<Utf8> optionsJson,
    Pointer<Pointer<Int32>> idBuffers,
    Pointer<IntPtr> idBufferSizes,
    Pointer<Pointer<Float>> scoreBuffers,
    Pointer<IntPtr> scoreBufferSizes);

typedef CactusIndexCompactNative = Int32 Function(CactusIndex index);
typedef CactusIndexCompactDart = int Function(CactusIndex index);

typedef CactusIndexDestroyNative = Void Function(CactusIndex index);
typedef CactusIndexDestroyDart = void Function(CactusIndex index);

typedef CactusSetTelemetryEnvironmentNative = Void Function(
    Pointer<Utf8> framework, Pointer<Utf8> cacheLocation, Pointer<Utf8> version);
typedef CactusSetTelemetryEnvironmentDart = void Function(
    Pointer<Utf8> framework, Pointer<Utf8> cacheLocation, Pointer<Utf8> version);

typedef CactusSetAppIdNative = Void Function(Pointer<Utf8> appId);
typedef CactusSetAppIdDart = void Function(Pointer<Utf8> appId);

typedef CactusTelemetryFlushNative = Void Function();
typedef CactusTelemetryFlushDart = void Function();

typedef CactusTelemetryShutdownNative = Void Function();
typedef CactusTelemetryShutdownDart = void Function();

typedef CactusLogSetLevelNative = Void Function(Int32 level);
typedef CactusLogSetLevelDart = void Function(int level);

typedef CactusLogSetCallbackNative = Void Function(
    Pointer<NativeFunction<CactusLogCallbackNative>> callback, Pointer<Void> userData);
typedef CactusLogSetCallbackDart = void Function(
    Pointer<NativeFunction<CactusLogCallbackNative>> callback, Pointer<Void> userData);
