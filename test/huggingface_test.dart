import 'package:cactus/cactus.dart';
import 'package:test/test.dart';

void main() {
  group('SemverVersion', () {
    test('compareTo with different major', () {
      expect(SemverVersion(2, 0, 0).compareTo(SemverVersion(1, 0, 0)), greaterThan(0));
      expect(SemverVersion(1, 0, 0).compareTo(SemverVersion(2, 0, 0)), lessThan(0));
    });

    test('compareTo with different minor', () {
      expect(SemverVersion(1, 14, 0).compareTo(SemverVersion(1, 13, 0)), greaterThan(0));
      expect(SemverVersion(1, 13, 0).compareTo(SemverVersion(1, 14, 0)), lessThan(0));
    });

    test('compareTo with different patch', () {
      expect(SemverVersion(1, 14, 1).compareTo(SemverVersion(1, 14, 0)), greaterThan(0));
      expect(SemverVersion(1, 14, 0).compareTo(SemverVersion(1, 14, 1)), lessThan(0));
    });

    test('compareTo with equal versions', () {
      expect(SemverVersion(1, 14, 0).compareTo(SemverVersion(1, 14, 0)), equals(0));
    });

    test('<= operator', () {
      expect(SemverVersion(1, 13, 0) <= SemverVersion(1, 14, 0), isTrue);
      expect(SemverVersion(1, 14, 0) <= SemverVersion(1, 14, 0), isTrue);
      expect(SemverVersion(1, 15, 0) <= SemverVersion(1, 14, 0), isFalse);
    });

    test('toString', () {
      expect(SemverVersion(1, 14, 0).toString(), equals('1.14.0'));
      expect(SemverVersion(1, 7, 0).toString(), equals('1.7.0'));
    });
  });

  group('HuggingFace.parseSemver', () {
    test('parses 3-part semver', () {
      final sv = HuggingFace.parseSemver('1.14.0');
      expect(sv, isNotNull);
      expect(sv!.major, equals(1));
      expect(sv.minor, equals(14));
      expect(sv.patch, equals(0));
    });

    test('parses 2-part semver with patch defaulting to 0', () {
      final sv = HuggingFace.parseSemver('1.14');
      expect(sv, isNotNull);
      expect(sv!.major, equals(1));
      expect(sv.minor, equals(14));
      expect(sv.patch, equals(0));
    });

    test('parses 1.7 as 1.7.0', () {
      final sv = HuggingFace.parseSemver('1.7');
      expect(sv, isNotNull);
      expect(sv!.major, equals(1));
      expect(sv.minor, equals(7));
      expect(sv.patch, equals(0));
    });

    test('returns null for invalid input', () {
      expect(HuggingFace.parseSemver('abc'), isNull);
      expect(HuggingFace.parseSemver('1'), isNull);
      expect(HuggingFace.parseSemver('1.'), isNull);
      expect(HuggingFace.parseSemver('.14'), isNull);
      expect(HuggingFace.parseSemver(''), isNull);
      expect(HuggingFace.parseSemver('v1.14'), isNull);
    });

    test('2-part and 3-part semvers with same major/minor are equal', () {
      final two = HuggingFace.parseSemver('1.14');
      final three = HuggingFace.parseSemver('1.14.0');
      expect(two, isNotNull);
      expect(three, isNotNull);
      expect(two!.compareTo(three!), equals(0));
    });
  });

  group('HuggingFace.constructDownloadUrl', () {
    test('constructs correct URL without double org', () {
      final url = HuggingFace.constructDownloadUrl(
        repoId: 'Cactus-Compute/Qwen3-0.6B',
        version: 'v1.14',
        key: 'qwen3-0.6b',
        quantization: 'int4',
      );
      expect(url, equals('https://huggingface.co/Cactus-Compute/Qwen3-0.6B/resolve/v1.14/weights/qwen3-0.6b-int4.zip'));
      expect(url, isNot(contains('Cactus-Compute/Cactus-Compute')));
    });

    test('constructs correct URL with int8', () {
      final url = HuggingFace.constructDownloadUrl(
        repoId: 'Cactus-Compute/Qwen3-0.6B',
        version: 'v1.14',
        key: 'qwen3-0.6b',
        quantization: 'int8',
      );
      expect(url, equals('https://huggingface.co/Cactus-Compute/Qwen3-0.6B/resolve/v1.14/weights/qwen3-0.6b-int8.zip'));
    });

    test('constructs apple URL with -apple suffix', () {
      final url = HuggingFace.constructDownloadUrl(
        repoId: 'Cactus-Compute/LFM2-VL-450M',
        version: 'v1.14',
        key: 'lfm2-vl-450m',
        quantization: 'int4',
        apple: true,
      );
      expect(url, equals('https://huggingface.co/Cactus-Compute/LFM2-VL-450M/resolve/v1.14/weights/lfm2-vl-450m-int4-apple.zip'));
    });

    test('no apple suffix when apple is false', () {
      final url = HuggingFace.constructDownloadUrl(
        repoId: 'Cactus-Compute/LFM2-VL-450M',
        version: 'v1.14',
        key: 'lfm2-vl-450m',
        quantization: 'int4',
        apple: false,
      );
      expect(url, isNot(contains('-apple')));
    });

    test('uses 2-part version tag from resolveVersion', () {
      final url = HuggingFace.constructDownloadUrl(
        repoId: 'Cactus-Compute/silero-vad',
        version: 'v1.7',
        key: 'silero-vad',
        quantization: 'int4',
      );
      expect(url, equals('https://huggingface.co/Cactus-Compute/silero-vad/resolve/v1.7/weights/silero-vad-int4.zip'));
      expect(url, isNot(contains('v1.7.0')));
    });
  });

  group('HuggingFace.extractCapabilities', () {
    test('extracts known capabilities from tags', () {
      final tags = ['Qwen3-0.6B', 'completion', 'tools', 'embed', 'text-generation', 'base_model:Qwen/Qwen3-0.6B'];
      final caps = HuggingFace.extractCapabilities(tags);
      expect(caps, containsAll(['completion', 'tools', 'embed']));
      expect(caps, isNot(contains('Qwen3-0.6B')));
      expect(caps, isNot(contains('text-generation')));
      expect(caps, isNot(contains('base_model:Qwen/Qwen3-0.6B')));
    });

    test('filters out HuggingFace pipeline tags', () {
      final tags = ['nomic-embed-text-v2-moe', 'embed', 'feature-extraction', 'base_model:nomic-ai/nomic-embed-text-v2-moe'];
      final caps = HuggingFace.extractCapabilities(tags);
      expect(caps, equals(['embed']));
      expect(caps, isNot(contains('feature-extraction')));
    });

    test('extracts vision and apple-npu capabilities', () {
      final tags = ['LFM2-VL-450M', 'vision', 'text-embed', 'image-embed', 'apple-npu', 'image-text-to-text'];
      final caps = HuggingFace.extractCapabilities(tags);
      expect(caps, containsAll(['vision', 'text-embed', 'image-embed', 'apple-npu']));
      expect(caps, isNot(contains('image-text-to-text')));
    });

    test('extracts vad capability from silero-vad', () {
      final tags = ['silero-vad', 'vad', 'voice-activity-detection', 'license:mit'];
      final caps = HuggingFace.extractCapabilities(tags);
      expect(caps, contains('vad'));
      expect(caps, isNot(contains('voice-activity-detection')));
      expect(caps, isNot(contains('silero-vad')));
    });

    test('extracts transcription and speech-embed from whisper', () {
      final tags = ['whisper-small', 'transcription', 'speech-embed', 'apple-npu', 'automatic-speech-recognition'];
      final caps = HuggingFace.extractCapabilities(tags);
      expect(caps, containsAll(['transcription', 'speech-embed', 'apple-npu']));
      expect(caps, isNot(contains('automatic-speech-recognition')));
    });

    test('returns empty list when no known capabilities', () {
      final tags = ['some-model', 'region:us', 'license:apache-2.0'];
      final caps = HuggingFace.extractCapabilities(tags);
      expect(caps, isEmpty);
    });

    test('handles audio capability', () {
      final tags = ['gemma-4-E2B-it', 'vision', 'audio', 'completion', 'tools', 'apple-npu', 'image-text-to-text'];
      final caps = HuggingFace.extractCapabilities(tags);
      expect(caps, containsAll(['vision', 'audio', 'completion', 'tools', 'apple-npu']));
      expect(caps, isNot(contains('image-text-to-text')));
    });
  });
}
