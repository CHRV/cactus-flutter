import 'dart:io';

import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/model_selector.dart';

class RAGPage extends StatefulWidget {
  const RAGPage({super.key});

  @override
  State<RAGPage> createState() => _RAGPageState();
}

class _RAGPageState extends State<RAGPage> {
  CactusLM? _lm;
  CactusLM get lm => _lm!;
  final TextEditingController _queryController = TextEditingController();

  bool isModelDownloaded = false;
  bool isModelLoaded = false;
  bool isDownloading = false;
  bool isInitializing = false;
  bool isSearching = false;
  String outputText = 'Ready to start. Select a model and click "Download Model" to begin.';
  List<ChunkSearchResult> searchResults = [];
  CactusModel? selectedModel;
  String selectedQuantization = 'int4';
  bool usePro = false;

  String? _corpusDir;

  @override
  void dispose() {
    _lm?.unload();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _setupCorpus() async {
    final dir = await getApplicationDocumentsDirectory();
    _corpusDir = '${dir.path}/corpus/test-rag';
    await Directory(_corpusDir!).create(recursive: true);

    await File('${_corpusDir!}/doc1.txt').writeAsString('The quick brown fox jumps over the lazy dog.');
    await File('${_corpusDir!}/doc2.txt').writeAsString('Machine learning enables computers to learn from data.');
    await File('${_corpusDir!}/doc3.txt').writeAsString('The capital of France is Paris.');
  }

  Future<void> downloadModel() async {
    if (selectedModel == null) return;
    setState(() {
      isDownloading = true;
      outputText = 'Downloading model...';
    });

    try {
      await _setupCorpus();

      _lm ??= CactusLM(
        model: selectedModel!.slug,
        corpusDir: _corpusDir,
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
    if (selectedModel == null) return;
    setState(() {
      isInitializing = true;
      outputText = 'Initializing model...';
    });

    try {
      await lm.initializeModel();
      setState(() {
        isModelLoaded = true;
        outputText = 'Model initialized successfully! You can now run RAG queries.';
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

  Future<void> searchDocuments() async {
    if (!isModelLoaded) {
      setState(() {
        outputText = 'Please download and initialize model first.';
      });
      return;
    }

    if (_queryController.text.isEmpty) {
      setState(() {
        outputText = 'Please enter a search query.';
      });
      return;
    }

    setState(() {
      isSearching = true;
      outputText = 'Searching documents...';
      searchResults = [];
    });

    try {
      final result = await lm.ragQuery(query: _queryController.text, topK: 3);

      setState(() {
        if (result.chunks.isNotEmpty) {
          searchResults = result.chunks.map((c) => ChunkSearchResult(
            text: c.content,
            score: c.score,
            metadata: {'source': c.source},
          )).toList();
          outputText = 'Found ${result.chunks.length} relevant chunks!';
        } else {
          searchResults = [];
          outputText = 'No relevant chunks found.';
        }
      });
    } catch (e) {
      setState(() {
        outputText = 'Error searching documents: $e';
      });
    } finally {
      setState(() {
        isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('RAG'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          ModelSelectorWidget(
            initialModel: 'qwen3-embedding-0.6b',
            capabilityFilter: 'embed',
            onModelSelected: (model) => setState(() { selectedModel = model; }),
            onQuantizationChanged: (q) => setState(() { selectedQuantization = q; }),
            onProChanged: (p) => setState(() { usePro = p; }),
          ),
          Expanded(
            child: SingleChildScrollView(
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
                            "RAG (Retrieval-Augmented Generation) Demo",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "This example demonstrates how to use the model's built-in RAG capabilities to search documents.",
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
                  const SizedBox(height: 20),
                  TextField(
                    controller: _queryController,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'Search Query',
                      labelStyle: TextStyle(color: Colors.grey),
                      hintText: 'Enter your question here...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.black),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: (isDownloading || isInitializing || isSearching || !isModelLoaded) ? null : searchDocuments,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: isSearching
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
                              Text('Searching...'),
                            ],
                          )
                        : const Text('Search'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Status: $outputText',
                    style: TextStyle(
                      color: outputText.contains('Error') ? Colors.red : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (searchResults.isNotEmpty) ...[
                    const Text(
                      'Search Results:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                    ),
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final result = searchResults[index];
                        return Card(
                          color: Colors.white,
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.grey, width: 0.5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (result.metadata?['source'] as String?) ?? 'Unknown Source',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  result.text,
                                  style: const TextStyle(fontSize: 14, color: Colors.black),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}