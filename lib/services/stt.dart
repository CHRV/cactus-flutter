import 'dart:async';

import 'package:cactus/models/types.dart';
import 'package:cactus/src/services/context.dart';
import 'package:cactus/src/utils/models/download.dart';
import 'package:cactus/src/services/api/supabase.dart';
import 'package:cactus/src/utils/speech/speech_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CactusSTT {
  int? _handle;
  String? _lastInitializedModel;
  static const String whisperPrompt = '<|startoftranscript|><|en|><|transcribe|><|notimestamps|>';
  CactusInitParams defaultInitParams = CactusInitParams();
  CactusTranscriptionParams defaultTranscriptionParams = CactusTranscriptionParams();
  final List<VoiceModel> _models = [];

  final _handleLock = _AsyncLock();

  Future<void> downloadModel({
    required String model,
    final CactusProgressCallback? downloadProcessCallback,
  }) async {
    if (await _isModelDownloaded(model)) {
      return;
    }

    final voiceModels = await Supabase.fetchVoiceModels();
    final currentModel = voiceModels.firstWhere(
      (m) => m.slug == model,
      orElse: () => throw Exception('Voice model $model not found'),
    );

    final task = DownloadTask(
      url: currentModel.downloadUrl,
      filename: currentModel.fileName,
      folder: currentModel.slug,
    );

    final success = await DownloadService.downloadAndExtractModels([task], downloadProcessCallback);
    if (!success) {
      throw Exception('Failed to download and extract voice model $model from ${currentModel.downloadUrl}');
    }
  }

  Future<void> initializeModel({final CactusInitParams? params}) async {
    final model = params?.model ?? _lastInitializedModel ?? defaultInitParams.model;
    final modelPath = '${(await getApplicationDocumentsDirectory()).path}/models/$model';

    final result = await CactusContext.initContext(modelPath, ((params?.contextSize) ?? defaultInitParams.contextSize));
    _handle = result.$1;

    if (_handle == null && !await _isModelDownloaded(model)) {
      debugPrint('Failed to initialize model context with model at $modelPath, trying to download the model first.');
      await downloadModel(model: model);
      return initializeModel(params: params);
    }

    if (_handle == null) {
      throw Exception('Failed to initialize model context with model at $modelPath');
    }
    _lastInitializedModel = model;
  }

  Future<CactusTranscriptionResult> transcribe({
    String? audioFilePath,
    Stream<Uint8List>? audioStream,
    Function(CactusTranscriptionResult)? onChunk,
    String prompt = whisperPrompt,
    CactusTranscriptionParams? params,
  }) async {
    if (audioFilePath == null && audioStream == null) {
      throw ArgumentError('Must provide either audioFilePath or audioStream');
    }
    
    if (audioFilePath != null && audioStream != null) {
      throw ArgumentError('Cannot provide both audioFilePath and audioStream');
    }

    if (audioFilePath != null) {
      return await _handleLock.synchronized(() async {
        final transcriptionParams = params ?? defaultTranscriptionParams;
        final model = _lastInitializedModel ?? defaultInitParams.model;
        final currentHandle = await _getValidatedHandle(model: model);

        if (currentHandle != null) {
          try {
            final result = await CactusContext.transcribe(
              currentHandle,
              prompt,
              audioFilePath: audioFilePath,
              params: transcriptionParams,
            );
            return result;
          } catch (e) {
            debugPrint('Transcription failed: $e');
            rethrow;
          }
        }

        throw Exception('Model $_lastInitializedModel is not downloaded. Please download it before transcribing.');
      });
    }

    final List<int> buffer = [];
    final completer = Completer<CactusTranscriptionResult>();

    final subscription = audioStream!.listen(
      (pcmChunk) {
        buffer.addAll(pcmChunk);
      },
      onError: (error) {
        debugPrint('Audio stream error: $error');
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () async {
        if (buffer.isEmpty) {
          debugPrint('No audio data received');
          if (!completer.isCompleted) {
            completer.complete(CactusTranscriptionResult(
              success: false,
              text: '',
              errorMessage: 'No audio data received',
            ));
          }
          return;
        }

        final pcmData = PCMUtils.validatePCMBuffer(buffer)
            ? buffer
            : PCMUtils.trimToValidSamples(buffer);

        if (pcmData.isEmpty) {
          debugPrint('No valid audio data after trimming');
          if (!completer.isCompleted) {
            completer.complete(CactusTranscriptionResult(
              success: false,
              text: '',
              errorMessage: 'No valid audio data received',
            ));
          }
          return;
        }

        try {
          final result = await _transcribePCMInternal(pcmData, prompt, params);
          if (!completer.isCompleted) {
            completer.complete(result);
          }
          onChunk?.call(result);
        } catch (e) {
          debugPrint('Failed to transcribe audio: $e');
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      },
    );

    completer.future.whenComplete(() => subscription.cancel());

    return completer.future;
  }

  Future<CactusStreamedTranscriptionResult> transcribeStream({
    String? audioFilePath,
    Stream<Uint8List>? audioStream,
    String prompt = whisperPrompt,
    CactusTranscriptionParams? params,
  }) async {
    if (audioFilePath == null && audioStream == null) {
      throw ArgumentError('Must provide either audioFilePath or audioStream');
    }
    
    if (audioFilePath != null && audioStream != null) {
      throw ArgumentError('Cannot provide both audioFilePath and audioStream');
    }

    if (audioFilePath != null) {
      final transcriptionParams = params ?? defaultTranscriptionParams;
      final model = _lastInitializedModel ?? defaultInitParams.model;
      final currentHandle = await _getValidatedHandle(model: model);

      if (currentHandle != null) {
        try {
          final streamedResult = CactusContext.transcribeStream(
            currentHandle,
            prompt,
            audioFilePath: audioFilePath,
            params: transcriptionParams,
          );
          return streamedResult;
        } catch (e) {
          debugPrint('Streaming transcription failed: $e');
          rethrow;
        }
      }

      throw Exception('Model $_lastInitializedModel is not downloaded. Please download it before transcribing.');
    }

    final tokenController = StreamController<String>();
    final resultCompleter = Completer<CactusTranscriptionResult>();
    final List<int> buffer = [];

    final subscription = audioStream!.listen(
      (pcmChunk) {
        buffer.addAll(pcmChunk);
      },
      onError: (error) {
        debugPrint('Audio stream error: $error');
        if (!tokenController.isClosed) {
          tokenController.addError(error);
        }
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(error);
        }
      },
      onDone: () async {
        if (buffer.isEmpty) {
          debugPrint('No audio data received');
          if (!tokenController.isClosed) {
            tokenController.close();
          }
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(CactusTranscriptionResult(
              success: false,
              text: '',
              errorMessage: 'No audio data received',
            ));
          }
          return;
        }

        final pcmData = PCMUtils.validatePCMBuffer(buffer)
            ? buffer
            : PCMUtils.trimToValidSamples(buffer);

        if (pcmData.isEmpty) {
          debugPrint('No valid audio data after trimming');
          if (!tokenController.isClosed) {
            tokenController.close();
          }
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(CactusTranscriptionResult(
              success: false,
              text: '',
              errorMessage: 'No valid audio data received',
            ));
          }
          return;
        }

        try {
          final streamedResult = await _transcribePCMStreamInternal(pcmData, prompt, params);

          streamedResult.stream.listen(
            (token) {
              if (!tokenController.isClosed) {
                tokenController.add(token);
              }
            },
            onError: (error) {
              if (!tokenController.isClosed) {
                tokenController.addError(error);
              }
            },
            onDone: () {
              if (!tokenController.isClosed) {
                tokenController.close();
              }
            },
          );

          final result = await streamedResult.result;
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(result);
          }
        } catch (e) {
          debugPrint('Failed to transcribe audio: $e');
          if (!tokenController.isClosed) {
            tokenController.addError(e);
            tokenController.close();
          }
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(e);
          }
        }
      },
    );

    resultCompleter.future.whenComplete(() => subscription.cancel());

    return CactusStreamedTranscriptionResult(
      stream: tokenController.stream,
      result: resultCompleter.future,
    );
  }

  Future<CactusTranscriptionResult> _transcribePCMInternal(
    List<int> pcmData,
    String prompt,
    CactusTranscriptionParams? params,
  ) async {
    if (pcmData.isEmpty) {
      debugPrint('ERROR: Cannot transcribe empty PCM data');
      return CactusTranscriptionResult(
        success: false,
        text: '',
        errorMessage: 'Empty PCM data provided',
      );
    }

    return await _handleLock.synchronized(() async {
      final transcriptionParams = params ?? defaultTranscriptionParams;
      final model = _lastInitializedModel ?? defaultInitParams.model;
      final currentHandle = await _getValidatedHandle(model: model);

      if (currentHandle != null) {
        reset();

        try {
          final result = await CactusContext.transcribe(
            currentHandle,
            prompt,
            pcmData: pcmData,
            params: transcriptionParams,
          );
          return result;
        } catch (e) {
          debugPrint('PCM transcription failed: $e');
          rethrow;
        }
      }

      throw Exception('Model $_lastInitializedModel is not downloaded. Please download it before transcribing.');
    });
  }

  Future<CactusStreamedTranscriptionResult> _transcribePCMStreamInternal(
    List<int> pcmData,
    String prompt,
    CactusTranscriptionParams? params,
  ) async {
    if (pcmData.isEmpty) {
      debugPrint('ERROR: Cannot transcribe empty PCM data');
      final controller = StreamController<String>();
      controller.close();
      return CactusStreamedTranscriptionResult(
        stream: controller.stream,
        result: Future.value(CactusTranscriptionResult(
          success: false,
          text: '',
          errorMessage: 'Empty PCM data provided',
        )),
      );
    }

    final transcriptionParams = params ?? defaultTranscriptionParams;
    final model = _lastInitializedModel ?? defaultInitParams.model;
    final currentHandle = await _getValidatedHandle(model: model);

    if (currentHandle != null) {
      try {
        reset();

        final streamedResult = CactusContext.transcribeStream(
          currentHandle,
          prompt,
          pcmData: pcmData,
          params: transcriptionParams,
        );
        return streamedResult;
      } catch (e) {
        debugPrint('PCM streaming transcription failed: $e');
        rethrow;
      }
    }

    throw Exception('Model $_lastInitializedModel is not downloaded. Please download it before transcribing.');
  }

  void unload() {
    final currentHandle = _handle;
    if (currentHandle != null) {
      CactusContext.freeContext(currentHandle);
      _handle = null;
    }
  }

  void reset() {
    final currentHandle = _handle;
    if (currentHandle != null) {
      CactusContext.resetContext(currentHandle);
    }
  }

  bool isLoaded() => _handle != null;

  Future<List<VoiceModel>> getVoiceModels() async {
    if (_models.isEmpty) {
      _models.addAll(await Supabase.fetchVoiceModels());
      for (var model in _models) {
        model.isDownloaded = await _isModelDownloaded(model.slug);
      }
    }
    return _models;
  }

  Future<int?> _getValidatedHandle({required String model}) async {
    if (_handle != null && (model == _lastInitializedModel)) {
      return _handle;
    }

    await initializeModel(params: CactusInitParams(model: model));
    return _handle;
  }

  Future<bool> _isModelDownloaded(String modelName) async {
    return await DownloadService.modelExists(modelName);
  }
}

class _AsyncLock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() fn) async {
    while (_completer != null) {
      await _completer!.future;
    }

    _completer = Completer<void>();

    try {
      return await fn();
    } finally {
      final completer = _completer;
      _completer = null;
      completer?.complete();
    }
  }
}
