import 'package:cactus/cactus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(minutes: 5));
const _fcModel = 'functiongemma-270m-it';

void main() {
  group('CactusLM function calling integration', () {
    late CactusLM lm;

    setUpAll(() async {
      lm = CactusLM(
        model: _fcModel,
        options: const CactusModelOptions(quantization: 'int4'),
      );
      await lm.download();
      await lm.init();
    });

    tearDownAll(() async {
      lm.destroy();
    });

test('complete with tool call', () async {
      final result = await lm.complete(
        messages: [
          CactusLMMessage(
            role: 'system',
            content: 'You are a helpful assistant. When the user asks a question that requires a calculation, ALWAYS call the calculator tool with the appropriate expression.',
          ),
          CactusLMMessage(
            role: 'user',
            content: 'What is 2 + 2?',
          ),
        ],
        options: const CactusLMCompleteOptions(maxTokens: 512, forceTools: true),
        tools: [
          CactusLMTool(
            name: 'calculator',
            description: 'A simple calculator that evaluates mathematical expressions.',
            parameters: {
              'type': 'object',
              'properties': {
                'expression': {
                  'type': 'string',
                  'description': 'The mathematical expression to evaluate, e.g. "2 + 2"',
                },
              },
              'required': ['expression'],
            },
          ),
        ],
      );
      debugPrint('function call result: success=${result.success}, response="${result.response}", toolCalls=${result.toolCalls}, functionCalls=${result.functionCalls}');
      expect(result.success, isTrue);
      expect(result.toolCalls, isNotNull);
      expect(result.toolCalls!.isNotEmpty, isTrue);
    });

    test('complete with onToken callback', () async {
      final tokens = <String>[];
      final result = await lm.complete(
        messages: [
          CactusLMMessage(role: 'user', content: 'Say hi in one word.'),
        ],
        options: const CactusLMCompleteOptions(maxTokens: 16),
        onToken: (token) {
          tokens.add(token);
        },
      );
      expect(result.success, isTrue);
      expect(tokens, isNotEmpty);
    }, timeout: _timeout);
  });
}
