import 'dart:convert';

/// Describes a single parameter within a tool's JSON schema.
class ToolParameter {
  /// The JSON Schema type (e.g. `"string"`, `"integer"`).
  final String type;

  /// A human-readable explanation of what this parameter is for.
  final String description;

  /// Whether the caller must provide this parameter. Defaults to `false`.
  final bool required;

  /// Creates a [ToolParameter] with the given [type], [description], and
  /// optional [required] flag.
  ToolParameter({
    required this.type,
    required this.description,
    this.required = false,
  });

  /// Serializes this parameter to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'description': description,
      'required': required,
    };
  }

  /// Deserializes a [ToolParameter] from a JSON map.
  ///
  /// [json]: The source map containing `type`, `description`, and optionally
  /// `required` keys.
  /// Returns: A new [ToolParameter] instance.
  factory ToolParameter.fromJson(Map<String, dynamic> json) {
    return ToolParameter(
      type: json['type'] as String,
      description: json['description'] as String,
      required: json['required'] as bool? ?? false,
    );
  }
}

/// Represents a JSON Schema object that defines a tool's input parameters.
class ToolParametersSchema {
  /// The JSON Schema type (defaults to `"object"`).
  final String type;

  /// A map of parameter names to their [ToolParameter] definitions.
  final Map<String, ToolParameter> properties;

  /// A list of property names that are required, derived automatically from
  /// [properties] entries whose [ToolParameter.required] is `true`.
  final List<String> required;

  /// Creates a schema with the given [properties] and optional [type].
  ToolParametersSchema({
    this.type = 'object',
    required this.properties,
  }) : required = properties.entries
            .where((entry) => entry.value.required)
            .map((entry) => entry.key)
            .toList();

  /// Serializes this schema to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'properties': properties.map((k, v) => MapEntry(k, v.toJson())),
      'required': required,
    };
  }

  /// Deserializes a [ToolParametersSchema] from a JSON map.
  ///
  /// [json]: The source map containing `type` and `properties` keys.
  /// Returns: A new [ToolParametersSchema] instance.
  factory ToolParametersSchema.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>? ?? {};

    return ToolParametersSchema(
      type: json['type'] as String? ?? 'object',
      properties: properties.map(
        (k, v) =>
            MapEntry(k, ToolParameter.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

/// A tool definition in the format expected by OpenAI-compatible function-calling APIs.
class CactusTool {
  /// The unique name of the tool, used by the model to identify which tool to call.
  final String name;

  /// A description of what the tool does, used by the model to decide when to invoke it.
  final String description;

  /// The JSON Schema describing the tool's input parameters.
  final ToolParametersSchema parameters;

  /// Creates a [CactusTool] with the given [name], [description], and [parameters].
  CactusTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Serializes this tool to an OpenAI-compatible JSON map.
  Map<String, dynamic> toJson() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters.toJson(),
      }
    };
  }

  /// Deserializes a [CactusTool] from an OpenAI-compatible JSON map.
  ///
  /// [json]: The source map containing a `function` key with `name`,
  /// `description`, and `parameters` sub-keys.
  /// Returns: A new [CactusTool] instance.
  factory CactusTool.fromJson(Map<String, dynamic> json) {
    final function = json['function'] as Map<String, dynamic>;
    return CactusTool(
      name: function['name'] as String,
      description: function['description'] as String,
      parameters: ToolParametersSchema.fromJson(
          function['parameters'] as Map<String, dynamic>),
    );
  }
}

/// Represents the result of a tool call: which tool was invoked and with what arguments.
class ToolCall {
  /// The name of the tool that was called.
  final String name;

  /// The arguments passed to the tool, as a map of argument names to string values.
  final Map<String, String> arguments;

  /// Creates a [ToolCall] with the given [name] and [arguments].
  ToolCall({
    required this.name,
    required this.arguments,
  });

  /// Serializes this tool call to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'arguments': arguments,
    };
  }

  /// Deserializes a [ToolCall] from a JSON map.
  ///
  /// [json]: The source map containing `name` and optionally `arguments` keys.
  /// Returns: A new [ToolCall] instance.
  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final args = json['arguments'] as Map<String, dynamic>? ?? {};
    return ToolCall(
      name: json['name'] as String,
      arguments: args.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// Convenience extension on [List] of [CactusTool] for serialization.
extension ToolListExtension on List<CactusTool> {
  /// Converts this list of tools to a JSON string using [jsonEncode].
  ///
  /// Returns: A JSON-encoded string representing the full tool list.
  String toToolsJson() {
    return jsonEncode(map((tool) => tool.toJson()).toList());
  }
}

/// Creates a [CactusTool] from raw parameters without needing to construct a
/// [ToolParametersSchema] manually.
///
/// [name]: The tool's name.
/// [description]: A description of what the tool does.
/// [parameters]: A map of parameter names to [ToolParameter] definitions.
/// Returns: A new [CactusTool] instance with an inferred schema.
CactusTool createTool(
  String name,
  String description,
  Map<String, ToolParameter> parameters,
) {
  return CactusTool(
    name: name,
    description: description,
    parameters: ToolParametersSchema(
      properties: parameters,
    ),
  );
}
