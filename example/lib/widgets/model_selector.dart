import 'package:cactus/cactus.dart';
import 'package:flutter/material.dart';

class ModelSelectorWidget extends StatefulWidget {
  const ModelSelectorWidget({
    super.key,
    this.capabilityFilter,
    this.onModelSelected,
    this.onQuantizationChanged,
    this.onProChanged,
    this.initialModel,
  });

  final String? capabilityFilter;
  final ValueChanged<CactusModel?>? onModelSelected;
  final ValueChanged<String>? onQuantizationChanged;
  final ValueChanged<bool>? onProChanged;
  final String? initialModel;

  @override
  State<ModelSelectorWidget> createState() => _ModelSelectorWidgetState();
}

class _ModelSelectorWidgetState extends State<ModelSelectorWidget> {
  List<CactusModel> _models = [];
  CactusModel? _selectedModel;
  String _selectedQuantization = 'int4';
  bool _usePro = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final models = await HuggingFace.fetchModels();
      final filtered = widget.capabilityFilter != null
          ? models
              .where((m) => m.capabilities.contains(widget.capabilityFilter))
              .toList()
          : models;
      setState(() {
        _models = filtered;
        _isLoading = false;
        if (widget.initialModel != null) {
          _selectedModel =
              filtered.where((m) => m.slug == widget.initialModel).firstOrNull;
        }
        if (_selectedModel == null && filtered.isNotEmpty) {
          _selectedModel = filtered.first;
        }
        if (_selectedModel != null &&
            !_selectedModel!.quantization.containsKey(_selectedQuantization)) {
          _selectedQuantization = _selectedModel!.quantization.keys.first;
        }
      });
      widget.onModelSelected?.call(_selectedModel);
      widget.onQuantizationChanged?.call(_selectedQuantization);
      widget.onProChanged?.call(_usePro);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error loading models: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_models.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          widget.capabilityFilter != null
              ? 'No models found with "${widget.capabilityFilter}" capability'
              : 'No models available',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownMenu<String>(
          hintText: 'Select Model',
          expandedInsets: EdgeInsets.zero,
          initialSelection: _selectedModel?.slug,
          dropdownMenuEntries: _models
              .map((m) => DropdownMenuEntry(
                    value: m.slug,
                    label:
                        '${m.slug} (${m.quantization['int4']?.sizeMb ?? 0} MB)',
                  ))
              .toList(),
          onSelected: (String? value) {
            if (value != null) {
              final model = _models.where((m) => m.slug == value).firstOrNull;
              if (model != null) {
                setState(() {
                  _selectedModel = model;
                  if (!model.quantization.containsKey(_selectedQuantization)) {
                    _selectedQuantization = model.quantization.keys.first;
                  }
                  _usePro = false;
                });
                widget.onModelSelected?.call(model);
                widget.onQuantizationChanged?.call(_selectedQuantization);
                widget.onProChanged?.call(_usePro);
              }
            }
          },
        ),
        if (_selectedModel != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _selectedModel!.quantization.keys.map((key) {
              final info = _selectedModel!.quantization[key]!;
              final isSelected = key == _selectedQuantization;
              return ChoiceChip(
                label: Text(
                    '$key: ${info.sizeMb} MB${info.pro != null ? ' ★' : ''}'),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedQuantization = key;
                    _usePro = false;
                  });
                  widget.onQuantizationChanged?.call(key);
                  widget.onProChanged?.call(_usePro);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Switch(
                value: _usePro,
                onChanged:
                    (_selectedModel?.quantization[_selectedQuantization]?.pro !=
                            null)
                        ? (value) {
                            setState(() {
                              _usePro = value;
                            });
                            widget.onProChanged?.call(value);
                          }
                        : null,
              ),
              const Text('Apple-optimized (Pro)'),
            ],
          ),
        ],
      ],
    );
  }
}
