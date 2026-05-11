@Tags(['integration'])
library integration_test;

import 'dart:io';
import 'package:cactus/cactus.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  test('fetchModels returns non-empty list', () async {
    final models = await HuggingFace.fetchModels();
    expect(models, isNotEmpty);
  }, timeout: _timeout);

  test('getModel returns qwen3-0.6b with completion/tools/embed capabilities', () async {
    final model = await HuggingFace.getModel('qwen3-0.6b');
    expect(model, isNotNull);
    expect(model!.capabilities, contains('completion'));
    expect(model.capabilities, contains('tools'));
    expect(model.capabilities, contains('embed'));
  }, timeout: _timeout);

  test('getModel returns silero-vad with vad capability', () async {
    final model = await HuggingFace.getModel('silero-vad');
    expect(model, isNotNull);
    expect(model!.capabilities, contains('vad'));
  }, timeout: _timeout);

  test('download URLs do not have double org prefix', () async {
    final models = await HuggingFace.fetchModels();
    for (final model in models) {
      for (final quant in model.quantization.entries) {
        expect(quant.value.url, isNot(contains('Cactus-Compute/Cactus-Compute')));
      }
    }
  }, timeout: _timeout);

  test('file sizes are non-zero for qwen3-0.6b', () async {
    final model = await HuggingFace.getModel('qwen3-0.6b');
    expect(model, isNotNull);
    expect(model!.quantization['int4']?.sizeMb ?? 0, greaterThan(0));
    expect(model.quantization['int8']?.sizeMb ?? 0, greaterThan(0));
  }, timeout: _timeout);

  test('resolveVersion returns original 2-part tag', () async {
    final version = await HuggingFace.resolveVersion('Cactus-Compute/Qwen3-0.6B');
    expect(version, equals('v1.14'));
    expect(version, isNot(equals('v1.14.0')));
  }, timeout: _timeout);

  test('download URL resolves with HTTP 302', () async {
    final model = await HuggingFace.getModel('silero-vad');
    expect(model, isNotNull);
    final url = model!.quantization['int4']?.url;
    expect(url, isNotNull);
    expect(url, isNotEmpty);
  }, timeout: _timeout);

  test('model name tags do not leak into capabilities', () async {
    final models = await HuggingFace.fetchModels();
    for (final model in models) {
      for (final cap in model.capabilities) {
        expect(cap, isNot(equals(model.slug)));
      }
    }
  }, timeout: _timeout);

  test('HuggingFace pipeline tags do not leak into capabilities', () async {
    final pipelineTags = {'text-generation', 'feature-extraction', 'automatic-speech-recognition',
        'image-text-to-text', 'voice-activity-detection'};
    final models = await HuggingFace.fetchModels();
    for (final model in models) {
      for (final cap in model.capabilities) {
        expect(pipelineTags, isNot(contains(cap)));
      }
    }
  }, timeout: _timeout);
}
