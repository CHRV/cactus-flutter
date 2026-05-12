import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';
import '../widgets/model_selector.dart';

class FunctionCallingPage extends StatefulWidget {
  const FunctionCallingPage({super.key});

  @override
  State<FunctionCallingPage> createState() => _FunctionCallingPageState();
}

class _FunctionCallingPageState extends State<FunctionCallingPage> {
  CactusLM get lm => _lm!;
  CactusLM? _lm;
  bool isModelDownloaded = false;
  bool isModelLoaded = false;
  bool isDownloading = false;
  bool isInitializing = false;
  bool isGenerating = false;
  String outputText = 'Ready to start. Select a model and click "Download Model" to begin.';
  String? lastResponse;
  double? lastTPS;
  double? lastTTFT;
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

  Future<void> downloadModel() async {
    setState(() {
      isDownloading = true;
      outputText = 'Downloading model...';
    });
    try {
      _lm ??= CactusLM(
          model: selectedModel!.slug,
          options: CactusModelOptions(quantization: selectedQuantization, pro: usePro),
        );
      await lm.downloadModel(
        model: selectedModel!.slug,
        quantization: selectedQuantization,
        pro: usePro,
        onProgress: (progress, status, isError) {
          setState(() {
            if (isError) {
              outputText = 'Error: $status';
            } else {
              outputText = status;
              if (progress != null) {
                outputText += ' (${(progress * 100).toStringAsFixed(1)}%)';
              }
            }
          });
        },
      );
      setState(() {
        isModelDownloaded = true;
        outputText = 'Model downloaded successfully! Click "Initialize Model" to load it.';
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
    
    try {
      await lm.initializeModel(
        model: selectedModel!.slug
      );
      setState(() {
        isModelLoaded = true;
        outputText = 'Model initialized successfully! Ready to generate completions.';
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

  Future<void> toolCall() async {
    if (!isModelLoaded) {
      setState(() {
        outputText = 'Please download and initialize model first.';
      });
      return;
    }
    
    setState(() {
      isGenerating = true;
      outputText = 'Generating response...';
    });
    
    try {
      final resp = await lm.generateCompletion(
        messages: [ChatMessage(content: 'How is the weather in New York?', role: "user")],
        tools: [
          CactusLMTool(
            name: 'get_weather',
            description: 'Get weather for a location',
            parameters: {
              'location': {
                'type': 'string',
                'description': 'City name',
                'required': true,
              },
            },
          ),
        ],
      );
      
      if (resp.toolCalls?.isNotEmpty ?? false) {
          setState(() {
            lastResponse = 'Tool Call: ${resp.toolCalls!.last.name}\nArguments: ${resp.toolCalls!.last.arguments}';
            lastTPS = resp.tokensPerSecond;
            lastTTFT = resp.timeToFirstTokenMs;
            outputText = 'Generation completed successfully!';
          });
        } else {
          setState(() {
            outputText = 'Failed to generate response.';
            lastResponse = null;
            lastTPS = null;
            lastTTFT = null;
          });
        }
    } catch (e) {
      setState(() {
        outputText = 'Error generating response: $e';
        lastResponse = null;
        lastTPS = null;
        lastTTFT = null;
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
        title: const Text('Function Calling'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          ModelSelectorWidget(
            initialModel: 'qwen3-0.6b',
            capabilityFilter: 'tools',
            onModelSelected: (model) => setState(() { selectedModel = model; }),
            onQuantizationChanged: (q) => setState(() { selectedQuantization = q; }),
            onProChanged: (p) => setState(() { usePro = p; }),
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
                            "Function Calling Demo",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "This example demonstrates how the AI model can call structured functions. We'll ask about weather and see if the model generates a proper function call.",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: isDownloading ? null : downloadModel,
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Downloading...'),
                          ],
                        )
                      : Text(isModelDownloaded ? 'Model Downloaded ✓' : 'Download Model'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: isInitializing ? null : initializeModel,
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Initializing...'),
                          ],
                        )
                      : Text(isModelLoaded ? 'Model Initialized ✓' : 'Initialize Model'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: (isDownloading || isInitializing || isGenerating || !isModelLoaded) ? null : toolCall,
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Processing...'),
                          ],
                        )
                      : const Text('Run Function Calling Example'),
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
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                          ),
                          const SizedBox(height: 8),
                          Text(outputText, style: const TextStyle(color: Colors.black)),
                          if (lastResponse != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Response:',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                            ),
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
                                Column(
                                  children: [
                                    const Text('TTFT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                                    Text('${lastTTFT?.toStringAsFixed(2)} ms', style: const TextStyle(color: Colors.black)),
                                  ],
                                ),
                                Column(
                                  children: [
                                    const Text('TPS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                                    Text('${lastTPS?.toStringAsFixed(2)}', style: const TextStyle(color: Colors.black)),
                                  ],
                                ),
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
          ),
        ],
      ),
    );
  }
}