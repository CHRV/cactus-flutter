import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';

class FetchModelsPage extends StatefulWidget {
  const FetchModelsPage({super.key});

  @override
  State<FetchModelsPage> createState() => _FetchModelsPageState();
}

class _FetchModelsPageState extends State<FetchModelsPage> {
  final lm = CactusLM();
  List<CactusModel> availableModels = [];
  bool isLoading = false;
  String outputText = 'Click "Refresh" to load available models.';

  @override
  void initState() {
    super.initState();
    fetchModels();
  }

  Future<void> fetchModels() async {
    setState(() {
      isLoading = true;
      outputText = 'Fetching available models...';
    });

    try {
      await HuggingFace.refreshRegistry();
      final models = await lm.getModels();
      setState(() {
        availableModels = models;
        outputText =
            'Found ${models.length} available models. Browse the list below.';
      });
    } catch (e) {
      setState(() {
        outputText = 'Error fetching models: $e';
        availableModels = [];
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Color _capabilityColor(String cap) {
    switch (cap) {
      case 'tools':
        return Colors.purple;
      case 'vision':
        return Colors.blue;
      case 'embed':
        return Colors.teal;
      case 'embedding':
        return Colors.teal;
      case 'audio':
        return Colors.orange;
      case 'completion':
        return Colors.green;
      case 'chat':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> _downloadModel(
      CactusModel model, String quantization, bool pro) async {
    try {
      await lm.download(
        model: model.slug,
        quantization: quantization,
        pro: pro,
      );
      if (mounted) {
        setState(() {
          model.isDownloaded = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.slug} downloaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading ${model.slug}: $e')),
        );
      }
    }
  }

  Widget _buildModelCard(CactusModel model) {
    String selectedQuant = 'int4';
    bool usePro = false;

    return StatefulBuilder(
      builder: (context, setCardState) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      model.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: model.isDownloaded
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        model.isDownloaded ? 'Downloaded' : 'Available',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: model.isDownloaded
                                  ? Colors.green.shade800
                                  : Colors.grey.shade700,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Slug: ${model.slug}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (model.capabilities.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: model.capabilities
                        .map((cap) => Chip(
                              label: Text(cap),
                              labelStyle: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                              backgroundColor: _capabilityColor(cap),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: model.quantization.entries.map((entry) {
                    final isSelected = entry.key == selectedQuant;
                    return ChoiceChip(
                      label: Text(
                          '${entry.key}: ${entry.value.sizeMb} MB${entry.value.pro != null ? ' ★' : ''}'),
                      selected: isSelected,
                      onSelected: (_) {
                        setCardState(() {
                          selectedQuant = entry.key;
                          usePro = false;
                        });
                      },
                    );
                  }).toList(),
                ),
                if (model.quantization[selectedQuant]?.pro != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Switch(
                        value: usePro,
                        onChanged: (v) => setCardState(() {
                          usePro = v;
                        }),
                      ),
                      const Text('Apple-optimized (Pro)',
                          style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ],
                if (!model.isDownloaded) ...[
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () =>
                        _downloadModel(model, selectedQuant, usePro),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Download'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No models available',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try refreshing to fetch the latest models',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: fetchModels,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Fetch Models'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : fetchModels,
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Model Discovery",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Browse all available AI models. Each model has different capabilities, sizes, and performance characteristics.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "Status:",
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    outputText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: availableModels.isNotEmpty
                ? ListView.builder(
                    itemCount: availableModels.length,
                    itemBuilder: (context, index) {
                      return _buildModelCard(availableModels[index]);
                    },
                  )
                : !isLoading
                    ? _buildEmptyState()
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
          ),
        ],
      ),
    );
  }
}
