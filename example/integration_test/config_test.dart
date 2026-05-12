import 'package:cactus/cactus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CactusConfig', () {
    test('setAppId accepts valid string', () {
      // Should not throw
      CactusConfig.setAppId('test-app-id');
    });

    test('setAppId accepts empty string', () {
      // Should not throw
      CactusConfig.setAppId('');
    });

    test('telemetryFlush completes without error', () {
      // Returns void, just verify no exception is thrown
      CactusConfig.telemetryFlush();
    });

    test('telemetryShutdown completes without error', () {
      // Returns void, just verify no exception is thrown
      CactusConfig.telemetryShutdown();
    });

    test('logSetLevel accepts valid levels', () {
      // Level 0 = DEBUG, 1 = INFO, 2 = WARN, 3 = ERROR, 4 = NONE
      for (var level = 0; level <= 4; level++) {
        expect(() => CactusConfig.logSetLevel(level), returnsNormally);
      }
    });

    test('logSetLevel accepts out-of-range levels without crashing', () {
      // Negative level
      expect(() => CactusConfig.logSetLevel(-1), returnsNormally);
      // Very high level
      expect(() => CactusConfig.logSetLevel(99), returnsNormally);
    });
  });
}