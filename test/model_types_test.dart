import 'package:cactus/cactus.dart';
import 'package:test/test.dart';

void main() {
  group('CactusModel', () {
    test('supportsToolCalling returns true when tools in capabilities', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: ['completion', 'tools'],
        quantization: {
          'int4': CactusQuantizationInfo(sizeMb: 100, url: 'http://example.com/model-int4.zip'),
        },
      );
      expect(model.supportsToolCalling, isTrue);
    });

    test('supportsToolCalling returns false when tools not in capabilities', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: ['completion'],
        quantization: {
          'int4': CactusQuantizationInfo(sizeMb: 100, url: 'http://example.com/model-int4.zip'),
        },
      );
      expect(model.supportsToolCalling, isFalse);
    });

    test('supportsVision returns true when vision in capabilities', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: ['completion', 'vision'],
        quantization: {
          'int4': CactusQuantizationInfo(sizeMb: 100, url: 'http://example.com/model-int4.zip'),
        },
      );
      expect(model.supportsVision, isTrue);
    });

    test('supportsVision returns false when vision not in capabilities', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: ['completion'],
        quantization: {
          'int4': CactusQuantizationInfo(sizeMb: 100, url: 'http://example.com/model-int4.zip'),
        },
      );
      expect(model.supportsVision, isFalse);
    });

    test('sizeMb returns int4 size', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: [],
        quantization: {
          'int4': CactusQuantizationInfo(sizeMb: 359, url: 'http://example.com/model-int4.zip'),
          'int8': CactusQuantizationInfo(sizeMb: 574, url: 'http://example.com/model-int8.zip'),
        },
      );
      expect(model.sizeMb, equals(359));
    });

    test('sizeMb returns 0 when no int4 quantization', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: [],
        quantization: {
          'int8': CactusQuantizationInfo(sizeMb: 574, url: 'http://example.com/model-int8.zip'),
        },
      );
      expect(model.sizeMb, equals(0));
    });

    test('downloadUrl returns int4 url', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: [],
        quantization: {
          'int4': CactusQuantizationInfo(sizeMb: 100, url: 'http://example.com/model-int4.zip'),
        },
      );
      expect(model.downloadUrl, equals('http://example.com/model-int4.zip'));
    });

    test('downloadUrl returns empty string when no int4', () {
      final model = CactusModel(
        slug: 'test',
        name: 'test',
        capabilities: [],
        quantization: {},
      );
      expect(model.downloadUrl, equals(''));
    });

    test('fromJson/toJson round-trip', () {
      final original = CactusModel(
        slug: 'qwen3-0.6b',
        name: 'qwen3-0.6b',
        capabilities: ['completion', 'tools', 'embed'],
        quantization: {
          'int4': CactusQuantizationInfo(
            sizeMb: 359,
            url: 'https://huggingface.co/Cactus-Compute/Qwen3-0.6B/resolve/v1.14/weights/qwen3-0.6b-int4.zip',
          ),
          'int8': CactusQuantizationInfo(
            sizeMb: 574,
            url: 'https://huggingface.co/Cactus-Compute/Qwen3-0.6B/resolve/v1.14/weights/qwen3-0.6b-int8.zip',
          ),
        },
      );
      final json = original.toJson();
      final restored = CactusModel.fromJson(json);

      expect(restored.slug, equals(original.slug));
      expect(restored.name, equals(original.name));
      expect(restored.capabilities, equals(original.capabilities));
      expect(restored.quantization.keys, equals(original.quantization.keys));
      expect(restored.quantization['int4']!.sizeMb, equals(359));
      expect(restored.quantization['int4']!.url, contains('qwen3-0.6b-int4.zip'));
      expect(restored.quantization['int8']!.sizeMb, equals(574));
    });

    test('fromJson with pro info', () {
      final json = {
        'slug': 'lfm2-vl-450m',
        'name': 'lfm2-vl-450m',
        'capabilities': ['vision', 'text-embed', 'apple-npu'],
        'quantization': {
          'int4': {
            'size_mb': 200,
            'url': 'http://example.com/model-int4.zip',
            'pro': {'apple': 'http://example.com/model-int4-apple.zip'},
          },
        },
      };
      final model = CactusModel.fromJson(json);
      expect(model.quantization['int4']!.pro, isNotNull);
      expect(model.quantization['int4']!.pro!.apple, equals('http://example.com/model-int4-apple.zip'));
    });
  });

  group('CactusQuantizationInfo', () {
    test('fromJson/toJson round-trip', () {
      final original = CactusQuantizationInfo(
        sizeMb: 359,
        url: 'https://example.com/model-int4.zip',
        pro: CactusProInfo(apple: 'https://example.com/model-int4-apple.zip'),
      );
      final json = original.toJson();
      final restored = CactusQuantizationInfo.fromJson(json);

      expect(restored.sizeMb, equals(359));
      expect(restored.url, equals(original.url));
      expect(restored.pro, isNotNull);
      expect(restored.pro!.apple, equals(original.pro!.apple));
    });

    test('fromJson without pro', () {
      final json = {
        'size_mb': 100,
        'url': 'https://example.com/model-int4.zip',
      };
      final restored = CactusQuantizationInfo.fromJson(json);
      expect(restored.sizeMb, equals(100));
      expect(restored.pro, isNull);
    });
  });
}
