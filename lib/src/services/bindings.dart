import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:cactus/src/models/binding.dart';

String _getLibraryPath(String libName) {
  if (Platform.isIOS || Platform.isMacOS) {
    return '$libName.framework/$libName';
  }
  if (Platform.isAndroid) {
    return 'lib$libName.so';
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

final DynamicLibrary cactusLib = DynamicLibrary.open(_getLibraryPath('cactus'));

final cactusInit = cactusLib
    .lookupFunction<CactusInitNative, CactusInitDart>('cactus_init');

final cactusComplete = cactusLib
    .lookupFunction<CactusCompleteNative, CactusCompleteDart>('cactus_complete');

final cactusPrefill = cactusLib
    .lookupFunction<CactusPrefillNative, CactusPrefillDart>('cactus_prefill');

final cactusDestroy = cactusLib
    .lookupFunction<CactusDestroyNative, CactusDestroyDart>('cactus_destroy');

final cactusReset = cactusLib
    .lookupFunction<CactusResetNative, CactusResetDart>('cactus_reset');

final cactusStop = cactusLib
    .lookupFunction<CactusStopNative, CactusStopDart>('cactus_stop');

final cactusGetLastError = cactusLib
    .lookupFunction<CactusGetLastErrorNative, CactusGetLastErrorDart>('cactus_get_last_error');

final cactusEmbed = cactusLib
    .lookupFunction<CactusEmbedNative, CactusEmbedDart>('cactus_embed');

final cactusImageEmbed = cactusLib
    .lookupFunction<CactusImageEmbedNative, CactusImageEmbedDart>('cactus_image_embed');

final cactusAudioEmbed = cactusLib
    .lookupFunction<CactusAudioEmbedNative, CactusAudioEmbedDart>('cactus_audio_embed');

final cactusTranscribe = cactusLib
    .lookupFunction<CactusTranscribeNative, CactusTranscribeDart>('cactus_transcribe');

final cactusDetectLanguage = cactusLib
    .lookupFunction<CactusDetectLanguageNative, CactusDetectLanguageDart>('cactus_detect_language');

final cactusVad = cactusLib
    .lookupFunction<CactusVadNative, CactusVadDart>('cactus_vad');

final cactusDiarize = cactusLib
    .lookupFunction<CactusDiarizeNative, CactusDiarizeDart>('cactus_diarize');

final cactusEmbedSpeaker = cactusLib
    .lookupFunction<CactusEmbedSpeakerNative, CactusEmbedSpeakerDart>('cactus_embed_speaker');

final cactusStreamTranscribeStart = cactusLib
    .lookupFunction<CactusStreamTranscribeStartNative, CactusStreamTranscribeStartDart>('cactus_stream_transcribe_start');

final cactusStreamTranscribeProcess = cactusLib
    .lookupFunction<CactusStreamTranscribeProcessNative, CactusStreamTranscribeProcessDart>('cactus_stream_transcribe_process');

final cactusStreamTranscribeStop = cactusLib
    .lookupFunction<CactusStreamTranscribeStopNative, CactusStreamTranscribeStopDart>('cactus_stream_transcribe_stop');

final cactusTokenize = cactusLib
    .lookupFunction<CactusTokenizeNative, CactusTokenizeDart>('cactus_tokenize');

final cactusScoreWindow = cactusLib
    .lookupFunction<CactusScoreWindowNative, CactusScoreWindowDart>('cactus_score_window');

final cactusRagQuery = cactusLib
    .lookupFunction<CactusRagQueryNative, CactusRagQueryDart>('cactus_rag_query');

final cactusIndexInit = cactusLib
    .lookupFunction<CactusIndexInitNative, CactusIndexInitDart>('cactus_index_init');

final cactusIndexAdd = cactusLib
    .lookupFunction<CactusIndexAddNative, CactusIndexAddDart>('cactus_index_add');

final cactusIndexDelete = cactusLib
    .lookupFunction<CactusIndexDeleteNative, CactusIndexDeleteDart>('cactus_index_delete');

final cactusIndexGet = cactusLib
    .lookupFunction<CactusIndexGetNative, CactusIndexGetDart>('cactus_index_get');

final cactusIndexQuery = cactusLib
    .lookupFunction<CactusIndexQueryNative, CactusIndexQueryDart>('cactus_index_query');

final cactusIndexCompact = cactusLib
    .lookupFunction<CactusIndexCompactNative, CactusIndexCompactDart>('cactus_index_compact');

final cactusIndexDestroy = cactusLib
    .lookupFunction<CactusIndexDestroyNative, CactusIndexDestroyDart>('cactus_index_destroy');

final cactusSetTelemetryEnvironment = cactusLib
    .lookupFunction<CactusSetTelemetryEnvironmentNative, CactusSetTelemetryEnvironmentDart>('cactus_set_telemetry_environment');

final cactusSetAppId = cactusLib
    .lookupFunction<CactusSetAppIdNative, CactusSetAppIdDart>('cactus_set_app_id');

final cactusTelemetryFlush = cactusLib
    .lookupFunction<CactusTelemetryFlushNative, CactusTelemetryFlushDart>('cactus_telemetry_flush');

final cactusTelemetryShutdown = cactusLib
    .lookupFunction<CactusTelemetryShutdownNative, CactusTelemetryShutdownDart>('cactus_telemetry_shutdown');

final cactusLogSetLevel = cactusLib
    .lookupFunction<CactusLogSetLevelNative, CactusLogSetLevelDart>('cactus_log_set_level');

final cactusLogSetCallback = cactusLib
    .lookupFunction<CactusLogSetCallbackNative, CactusLogSetCallbackDart>('cactus_log_set_callback');
