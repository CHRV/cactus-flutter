import 'dart:io';
import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../widgets/model_selector.dart';
import '../widgets/download_panel.dart';

class VisionPage extends StatefulWidget {
  const VisionPage({super.key});

  @override
  State<VisionPage> createState() => _VisionPageState();
}

class _VisionPageState extends State<VisionPage> {
  CactusLM get lm => _lm!;
  CactusLM? _lm;
  bool isModelDownloaded = false;
  bool isModelLoaded = false;
  bool isDownloading = false;
  bool isInitializing = false;
  bool isGenerating = false;
  bool isStreaming = false;
  String outputText = 'Ready to start. Select a vision model and pick an image.';
  DownloadHandle? _currentDownload;
  String? lastResponse;
  double lastTPS = 0;
  double lastTTFT = 0;
  CactusModel? selectedModel;
  String selectedQuantization = 'int4';
  bool usePro = false;
  String? selectedImagePath;

  @override
  void dispose() {
    _lm?.unload();
    super.dispose();
  }

  Future<String?> pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'gallery_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = p.join(appDir.path, 'images', fileName);
      final imageDir = Directory(p.dirname(savedPath));
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      await File(image.path).copy(savedPath);
      return savedPath;
    }
    return null;
  }

  Future<void> handleImagePick() async {
    final path = await pickImageFromGallery();
    if (path != null) {
      setState(() {
        selectedImagePath = path;
        outputText = 'Image selected! Click "Download Model" if needed, then "Analyze Image".';
      });
    }
  }

  Future<void> download() async {
    if (selectedModel == null) {
      setState(() => outputText = 'Please select a vision model first.');
      return;
    }
    setState(() {
      isDownloading = true;
      outputText = 'Downloading model...';
    });
    try {
      _lm = CactusLM(
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
      setState(() => _currentDownload = handle);
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
      setState(() => outputText = 'Please select a vision model first.');
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
      await lm.initializeModel(model: selectedModel!.slug);
      setState(() {
        isModelLoaded = true;
        outputText = 'Model initialized successfully! Pick an image to analyze.';
      });
    } catch (e) {
      setState(() => outputText = 'Error initializing model: $e');
    } finally {
      setState(() => isInitializing = false);
    }
  }

  Future<void> analyzeImage() async {
    if (!isModelLoaded) {
      setState(() => outputText = 'Please download and initialize model first.');
      return;
    }
    if (selectedImagePath == null) {
      setState(() => outputText = 'Please pick an image first.');
      return;
    }
    setState(() {
      isGenerating = true;
      isStreaming = false;
      outputText = 'Analyzing image...';
      lastResponse = '';
      lastTPS = 0;
      lastTTFT = 0;
    });
    try {
      final streamedResult = await lm.generateCompletionStream(
        params: CactusCompletionParams(maxTokens: 200),
        messages: [
          ChatMessage(content: 'You are a helpful AI assistant that can analyze images.', role: CactusLMRole.system),
          ChatMessage(content: 'Describe this image', role: CactusLMRole.user, images: [selectedImagePath!])
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
          outputText = 'Image analysis completed successfully!';
          isStreaming = false;
        });
      } else {
        setState(() {
          outputText = 'Failed to analyze image.';
          lastResponse = null;
          lastTPS = 0;
          lastTTFT = 0;
          isStreaming = false;
        });
      }
    } catch (e) {
      setState(() {
        outputText = 'Error analyzing image: $e';
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
        title: const Text('Vision Example'),
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
              capabilityFilter: 'vision',
              onModelSelected: (model) => setState(() {
                selectedModel = model;
                isModelDownloaded = false;
                isModelLoaded = false;
              }),
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
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
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
                          : Text(isModelDownloaded ? 'Downloaded ✓' : 'Download Model'),
                    ),
                  ),
                  const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (isInitializing || selectedModel == null) ? null : initializeModel,
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
                        : Text(isModelLoaded ? 'Initialized ✓' : 'Initialize Model'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: handleImagePick,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(selectedImagePath == null ? 'Pick Image' : 'Change Image'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (isDownloading || isInitializing || isGenerating || !isModelLoaded || selectedImagePath == null) ? null : analyzeImage,
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
                        : const Text('Analyze Image'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (selectedImagePath != null)
              Container(
                height: 150,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(selectedImagePath!), fit: BoxFit.contain),
                ),
              ),
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