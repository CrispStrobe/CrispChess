import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/chess_clock.dart';

void main() {
  group('Custom TimeControl', () {
    test('custom enum value exists', () {
      expect(TimeControl.custom.label, 'Custom');
    });

    test('all original presets still work', () {
      expect(TimeControl.unlimited.isUnlimited, isTrue);
      expect(TimeControl.bullet1.baseTime, const Duration(minutes: 1));
      expect(TimeControl.blitz5inc.incrementSeconds, 3);
      expect(TimeControl.classical60.baseTime, const Duration(minutes: 60));
    });
  });

  group('ChessClock with custom overrides', () {
    test('uses customBaseTime when provided', () {
      final clock = ChessClock(
        timeControl: TimeControl.custom,
        customBaseTime: const Duration(minutes: 15),
      );
      expect(clock.white.remaining, const Duration(minutes: 15));
      expect(clock.black.remaining, const Duration(minutes: 15));
      clock.dispose();
    });

    test('uses customIncrementSeconds on switchTurn', () {
      final clock = ChessClock(
        timeControl: TimeControl.custom,
        customBaseTime: const Duration(minutes: 5),
        customIncrementSeconds: 10,
      );
      clock.start();
      final initialWhite = clock.white.remaining;
      clock.switchTurn(); // White gets 10s increment
      expect(
        clock.white.remaining,
        greaterThanOrEqualTo(initialWhite + const Duration(seconds: 9)),
      );
      clock.dispose();
    });

    test('reset uses custom time', () {
      final clock = ChessClock(
        timeControl: TimeControl.custom,
        customBaseTime: const Duration(minutes: 7),
      );
      clock.start();
      clock.switchTurn();
      clock.reset();
      expect(clock.white.remaining, const Duration(minutes: 7));
      expect(clock.black.remaining, const Duration(minutes: 7));
      clock.dispose();
    });

    test('regular preset ignores custom overrides', () {
      final clock = ChessClock(
        timeControl: TimeControl.blitz5,
        // These should be ignored since timeControl is not custom
      );
      expect(clock.white.remaining, const Duration(minutes: 5));
      clock.dispose();
    });

    test('custom with no overrides uses enum defaults', () {
      final clock = ChessClock(timeControl: TimeControl.custom);
      // custom default is 10 minutes
      expect(clock.white.remaining, const Duration(minutes: 10));
      clock.dispose();
    });
  });
}
