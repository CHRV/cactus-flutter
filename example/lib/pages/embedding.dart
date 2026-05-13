import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';
import '../widgets/model_selector.dart';

class EmbeddingPage extends StatefulWidget {
  const EmbeddingPage({super.key});

  @override
  State<EmbeddingPage> createState() => _EmbeddingPageState();
}

class _EmbeddingPageState extends State<EmbeddingPage> {
  CactusLM get lm => _lm!;
  CactusLM? _lm;
  bool isModelDownloaded = false;
  bool isModelLoaded = false;
  bool isDownloading = false;
  bool isInitializing = false;
  bool isGenerating = false;
  String outputText =
      'Ready to start. Select a model and click "Download Model" to begin.';
  String? lastResponse;
  CactusModel? selectedModel;
  String selectedQuantization = 'int4';
  bool usePro = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _lm?.unload();
    super.dispose();
  }

  Future<void> download() async {
    if (isDownloading) return;
    if (selectedModel == null) {
      setState(() {
        outputText = 'Please select a model first.';
      });
      return;
    }
    setState(() {
      isDownloading = true;
    });
    try {
      _lm ??= CactusLM(
        model: selectedModel!.slug,
        options: CactusModelOptions(quantization: selectedQuantization, pro: usePro),
      );
      await lm.download(
        model: selectedModel!.slug,
        quantization: selectedQuantization,
        pro: usePro,
      );
      setState(() {
        isModelDownloaded = true;
        outputText =
            'Model downloaded successfully! Click "Initialize Model" to load it.';
      });
    } catch (e) {
      setState(() {
        outputText = 'Error downloading model: $e';
      });
    } finally {
      setState(() {
        isDownloading = false;
      });
    }
  }

  Future<void> initializeModel() async {
    setState(() {
      isInitializing = true;
      outputText = 'Initializing model...';
    });

    if (selectedModel == null) {
      setState(() {
        outputText = 'Please select a model first.';
      });
      return;
    }

    try {
      _lm ??= CactusLM(
        model: selectedModel!.slug,
        options: CactusModelOptions(quantization: selectedQuantization, pro: usePro),
      );
      await lm.initializeModel(model: selectedModel!.slug);
      setState(() {
        isModelLoaded = true;
        outputText =
            'Model initialized successfully! Ready to generate embeddings.';
      });
    } catch (e) {
      setState(() {
        outputText = 'Error initializing model: $e';
      });
    } finally {
      setState(() {
        isInitializing = false;
      });
    }
  }

  Future<void> generateEmbeddings() async {
    if (!isModelLoaded) {
      setState(() {
        outputText = 'Please download and initialize model first.';
      });
      return;
    }

    setState(() {
      isGenerating = true;
      outputText = 'Generating embeddings...';
    });

    try {
      final resp = await lm.generateEmbedding(
          text: 'This is a sample text for embedding generation');

      if (resp.embedding.isNotEmpty) {
        setState(() {
          lastResponse =
              "Dimensions: ${resp.embedding.length} \nLength: ${resp.embedding.length} \nEmbeddings: [${resp.embedding.take(5).join(', ')}...]";
          outputText = 'Embedding generation completed successfully!';
        });
      } else {
        setState(() {
          outputText = 'Failed to generate embedding.';
          lastResponse = null;
        });
      }
    } catch (e) {
      setState(() {
        outputText = 'Error generating embeddings: $e';
        lastResponse = null;
      });
    } finally {
      setState(() {
        isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Embedding Generation'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          ModelSelectorWidget(
            initialModel: 'qwen3-embedding-0.6b',
            capabilityFilter: 'embed',
            onModelSelected: (model) => setState(() {
              selectedModel = model;
            }),
            onQuantizationChanged: (q) => setState(() {
              selectedQuantization = q;
            }),
            onProChanged: (p) => setState(() {
              usePro = p;
            }),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Text Embedding Demo",
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Convert text into numerical vectors (embeddings) that capture semantic meaning. These vectors can be used for similarity search, clustering, and other ML tasks.",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Downloading...'),
                            ],
                          )
                        : Text(isModelDownloaded
                            ? 'Model Downloaded ✓'
                            : 'Download Model'),
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
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Initializing...'),
                            ],
                          )
                        : Text(isModelLoaded
                            ? 'Model Initialized ✓'
                            : 'Initialize Model'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: (isDownloading ||
                            isInitializing ||
                            isGenerating ||
                            !isModelLoaded)
                        ? null
                        : generateEmbeddings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: isGenerating
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Generating...'),
                            ],
                          )
                        : const Text('Run Embedding Generation Example'),
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
                          const Text(
                            'Output:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black),
                          ),
                          const SizedBox(height: 8),
                          Text(outputText,
                              style: const TextStyle(color: Colors.black)),
                          if (lastResponse != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Response:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(lastResponse!,
                                    style:
                                        const TextStyle(color: Colors.black)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
