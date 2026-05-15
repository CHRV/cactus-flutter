import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';
import '../widgets/model_selector.dart';
import '../widgets/download_panel.dart';

class StreamingCompletionPage extends StatefulWidget {
  const StreamingCompletionPage({super.key});

  @override
  State<StreamingCompletionPage> createState() =>
      _StreamingCompletionPageState();
}

class _StreamingCompletionPageState extends State<StreamingCompletionPage> {
  CactusLM get lm => _lm!;
  CactusLM? _lm;
  bool isModelDownloaded = false;
  bool isModelLoaded = false;
  bool isDownloading = false;
  bool isInitializing = false;
  bool isGenerating = false;
  bool isStreaming = false;
  String outputText = 'Ready to start. Click "Download Model" to begin.';
  DownloadHandle? _currentDownload;
  String? lastResponse;
  double lastTPS = 0;
  double lastTTFT = 0;
  CactusModel? selectedModel;
  String selectedQuantization = 'int4';
  bool usePro = false;

  @override
  void dispose() {
    _lm?.unload();
    super.dispose();
  }

  Future<void> download() async {
    if (selectedModel == null) {
      setState(() => outputText = 'Please select a model first.');
      return;
    }
    setState(() {
      isDownloading = true;
      outputText = 'Downloading model...';
    });
    try {
      _lm ??= CactusLM(
        model: selectedModel!.slug,
        options: CactusModelOptions(quantization: selectedQuantization, pro: usePro),
      );
      final handle = await lm.download(
        model: selectedModel!.slug,
        quantization: selectedQuantization,
        pro: usePro,
        onProgress: (progress, status, isError) {
          setState(() {
            if (isError) {
              outputText = 'Error: $status';
            } else {
              outputText = status;
              if (progress != null) outputText += ' (${(progress * 100).toStringAsFixed(1)}%)';
            }
          });
        },
      );
      if (handle != null) {
        setState(() => _currentDownload = handle);
      } else {
        _onDownloadCompleted();
        return;
      }
    } catch (e) {
      setState(() {
        isDownloading = false;
        outputText = 'Error downloading model: $e';
      });
    }
  }

  void _onDownloadCompleted() {
    setState(() {
      isDownloading = false;
      _currentDownload = null;
      isModelDownloaded = true;
      outputText = 'Model downloaded successfully! Click "Initialize Model" to load it.';
    });
  }

  void _onDownloadCancelled() {
    setState(() {
      isDownloading = false;
      _currentDownload = null;
      outputText = 'Download cancelled.';
    });
  }

  void _onDownloadFailed() {
    setState(() {
      isDownloading = false;
      _currentDownload = null;
      outputText = 'Download failed.';
    });
  }

  Future<void> initializeModel() async {
    if (selectedModel == null) {
      setState(() => outputText = 'Please select a model first.');
      return;
    }
    setState(() {
      isInitializing = true;
      outputText = 'Initializing model...';
    });
    try {
      _lm ??= CactusLM(
        model: selectedModel!.slug,
        options: CactusModelOptions(quantization: selectedQuantization, pro: usePro),
      );
      await lm.init();
      setState(() {
        isModelLoaded = true;
        outputText = 'Model initialized successfully! Ready to generate completions.';
      });
    } catch (e) {
      setState(() => outputText = 'Error initializing model: $e');
    } finally {
      setState(() => isInitializing = false);
    }
  }

  Future<void> generateStreamCompletion() async {
    if (!isModelLoaded) {
      setState(() => outputText = 'Please download and initialize model first.');
      return;
    }
    setState(() {
      isGenerating = true;
      isStreaming = false;
      outputText = 'Generating stream response...';
      lastResponse = '';
      lastTPS = 0;
      lastTTFT = 0;
    });
    try {
      final streamedResult = await lm.generateCompletionStream(
        messages: [
          ChatMessage(content: 'You are Cactus, a very capable AI assistant running offline on a smartphone', role: CactusLMRole.system),
          ChatMessage(content: 'Hi, how are you?', role: CactusLMRole.user)
        ],
      );
      await for (final chunk in streamedResult.stream) {
        setState(() {
          if (!isStreaming) {
            isGenerating = false;
            isStreaming = true;
            outputText = 'Streaming response...';
          }
          lastResponse = (lastResponse ?? '') + chunk;
        });
      }
      final resp = await streamedResult.result;
      if (resp.success) {
        setState(() {
          lastResponse = resp.response;
          lastTPS = resp.tokensPerSecond;
          lastTTFT = resp.timeToFirstTokenMs;
          outputText = 'Stream generation completed successfully!';
          isStreaming = false;
        });
      } else {
        setState(() {
          outputText = 'Failed to generate response.';
          lastResponse = null;
          lastTPS = 0;
          lastTTFT = 0;
          isStreaming = false;
        });
      }
    } catch (e) {
      setState(() {
        outputText = 'Error generating stream response: $e';
        lastResponse = null;
        lastTPS = 0;
        lastTTFT = 0;
        isStreaming = false;
      });
    } finally {
      setState(() {
        isGenerating = false;
        isStreaming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Streaming Completion'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ModelSelectorWidget(
              initialModel: 'qwen3-0.6b',
              capabilityFilter: 'completion',
              onModelSelected: (model) => setState(() => selectedModel = model),
              onQuantizationChanged: (q) => setState(() => selectedQuantization = q),
              onProChanged: (p) => setState(() => usePro = p),
            ),
            const SizedBox(height: 10),
            if (isDownloading && _currentDownload != null)
              DownloadPanel(
                handle: _currentDownload!,
                onCompleted: _onDownloadCompleted,
                onCancelled: _onDownloadCancelled,
                onFailed: _onDownloadFailed,
              )
            else
              ElevatedButton(
                onPressed: (isDownloading || selectedModel == null) ? null : download,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                child: isDownloading
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                          SizedBox(width: 8),
                          Text('Starting download...'),
                        ],
                      )
                    : Text(isModelDownloaded ? 'Model Downloaded ✓' : 'Download Model'),
              ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: (isInitializing || isDownloading || selectedModel == null) ? null : initializeModel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: isInitializing
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                        SizedBox(width: 8),
                        Text('Initializing...'),
                      ],
                    )
                  : Text(isModelLoaded ? 'Model Initialized ✓' : 'Initialize Model'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: (isDownloading || isInitializing || isGenerating || !isModelLoaded) ? null : generateStreamCompletion,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: isGenerating && !isStreaming
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                        SizedBox(width: 8),
                        Text('Processing...'),
                      ],
                    )
                  : const Text('Run Streaming Example'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Output:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
                    const SizedBox(height: 8),
                    Text(outputText, style: const TextStyle(color: Colors.black)),
                    if (lastResponse != null) ...[
                      const SizedBox(height: 16),
                      const Text('Response:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      const SizedBox(height: 4),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(lastResponse!, style: const TextStyle(color: Colors.black)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(children: [
                            const Text('Model', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                            Text(selectedModel?.slug ?? '', style: const TextStyle(color: Colors.black)),
                          ]),
                          Column(children: [
                            const Text('TTFT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                            Text('${lastTTFT.toStringAsFixed(2)} ms', style: const TextStyle(color: Colors.black)),
                          ]),
                          Column(children: [
                            const Text('TPS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                            Text(lastTPS.toStringAsFixed(2), style: const TextStyle(color: Colors.black)),
                          ]),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}