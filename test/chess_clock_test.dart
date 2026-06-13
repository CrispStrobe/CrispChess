import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/chess_clock.dart';

void main() {
  group('ChessClock', () {
    test('unlimited clock does not tick', () {
      final clock = ChessClock(timeControl: TimeControl.unlimited);
      expect(clock.isUnlimited, isTrue);
      clock.start();
      expect(clock.isStarted, isFalse); // start() is a no-op for unlimited
      clock.dispose();
    });

    test('creates with correct initial time', () {
      final clock = ChessClock(timeControl: TimeControl.blitz5);
      expect(clock.white.remaining, const Duration(minutes: 5));
      expect(clock.black.remaining, const Duration(minutes: 5));
      expect(clock.isStarted, isFalse);
      clock.dispose();
    });

    test('start sets white as active', () {
      final clock = ChessClock(timeControl: TimeControl.blitz5);
      clock.start();
      expect(clock.isStarted, isTrue);
      expect(clock.isWhiteTurn, isTrue);
      expect(clock.white.isRunning, isTrue);
      expect(clock.black.isRunning, isFalse);
      clock.dispose();
    });

    test('switchTurn toggles active player', () {
      final clock = ChessClock(timeControl: TimeControl.blitz5);
      clock.start();
      expect(clock.isWhiteTurn, isTrue);

      clock.switchTurn();
      expect(clock.isWhiteTurn, isFalse);
      expect(clock.white.isRunning, isFalse);
      expect(clock.black.isRunning, isTrue);

      clock.switchTurn();
      expect(clock.isWhiteTurn, isTrue);
      expect(clock.white.isRunning, isTrue);
      expect(clock.black.isRunning, isFalse);
      clock.dispose();
    });

    test('increment is added on switchTurn', () {
      final clock = ChessClock(timeControl: TimeControl.blitz5inc);
      // blitz5inc = 5+3 (3 second increment)
      clock.start();
      final initialWhite = clock.white.remaining;
      clock.switchTurn(); // White moved, gets 3s increment
      expect(
        clock.white.remaining,
        greaterThanOrEqualTo(initialWhite + const Duration(seconds: 2)),
      );
      clock.dispose();
    });

    test('pause stops both clocks', () {
      final clock = ChessClock(timeControl: TimeControl.blitz5);
      clock.start();
      clock.pause();
      expect(clock.white.isRunning, isFalse);
      expect(clock.black.isRunning, isFalse);
      clock.dispose();
    });

    test('reset returns to initial state', () {
      final clock = ChessClock(timeControl: TimeControl.blitz5);
      clock.start();
      clock.switchTurn();
      clock.reset();
      expect(clock.isStarted, isFalse);
      expect(clock.white.remaining, const Duration(minutes: 5));
      expect(clock.black.remaining, const Duration(minutes: 5));
      clock.dispose();
    });

    test('display formats correctly', () {
      final side = ClockSide(remaining: const Duration(minutes: 5, seconds: 30));
      expect(side.display, '5:30');

      final side2 = ClockSide(remaining: const Duration(seconds: 9));
      expect(side2.display, '0:09');

      final side3 = ClockSide(remaining: Duration.zero);
      expect(side3.display, '0:00');

      final side4 = ClockSide(remaining: const Duration(hours: 1, minutes: 30));
      expect(side4.display, '1:30:00');
    });

    test('isExpired when time runs out', () {
      final side = ClockSide(remaining: Duration.zero);
      expect(side.isExpired, isTrue);

      final side2 = ClockSide(remaining: const Duration(seconds: 1));
      expect(side2.isExpired, isFalse);
    });

    test('winner returns correct side on flag', () {
      final clock = ChessClock(timeControl: TimeControl.blitz5);
      expect(clock.winner, isNull);
      clock.white.remaining = Duration.zero;
      expect(clock.winner, 'Black');
      clock.white.remaining = const Duration(minutes: 5);
      clock.black.remaining = Duration.zero;
      expect(clock.winner, 'White');
      clock.dispose();
    });

    test('TimeControl values have correct properties', () {
      expect(TimeControl.unlimited.isUnlimited, isTrue);
      expect(TimeControl.bullet1.baseTime, const Duration(minutes: 1));
      expect(TimeControl.blitz5inc.incrementSeconds, 3);
      expect(TimeControl.rapid15.baseTime, const Duration(minutes: 15));
      expect(TimeControl.rapid15.incrementSeconds, 10);
    });
  });
}
