import 'package:crispchess/engines/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _budget(Duration remaining, int inc, int level) => clockAwareThinkTime(
      remaining: remaining,
      incrementSeconds: inc,
      skillLevel: level,
    );

void main() {
  group('clockAwareThinkTime', () {
    test('never spends enough to flag — always leaves a safety margin', () {
      for (final remSec in [60, 30, 10, 5, 2, 1]) {
        final rem = Duration(seconds: remSec);
        final b = _budget(rem, 0, 20);
        expect(b, lessThan(rem),
            reason: 'at ${remSec}s the budget must stay under remaining');
        // Well under: at most a quarter of the clock on any one move.
        expect(b.inMilliseconds, lessThanOrEqualTo(rem.inMilliseconds ~/ 4 + 1));
      }
    });

    test('repeatedly spending the budget never runs the clock out (bullet)', () {
      // Simulate a 1+0 bullet game at full strength: subtract each budget and
      // (no increment) continue. It must survive many moves.
      var rem = const Duration(minutes: 1);
      var moves = 0;
      while (rem > const Duration(milliseconds: 100) && moves < 500) {
        final b = _budget(rem, 0, 20);
        expect(b, lessThan(rem));
        rem -= b;
        moves++;
      }
      // Because each slice is ~1/30 of the (shrinking) clock, it takes many
      // moves to burn down — far more than a real game, i.e. it won't flag.
      expect(moves, greaterThan(60));
    });

    test('uses long clocks far beyond the flat per-level cap', () {
      // 30-minute game, full strength: should think much longer than the flat
      // 2s per-level maximum (but capped at the 30s app ceiling).
      final b = _budget(const Duration(minutes: 30), 0, 20);
      expect(b.inMilliseconds, greaterThan(thinkTimeForLevel(20).inMilliseconds));
      expect(b.inSeconds, greaterThanOrEqualTo(20));
      expect(b.inSeconds, lessThanOrEqualTo(30)); // UX cap
    });

    test('weak levels stay fast even with a big clock', () {
      final weak = _budget(const Duration(minutes: 30), 0, 0);
      final strong = _budget(const Duration(minutes: 30), 0, 20);
      expect(weak, lessThan(strong));
      // Level 0 stays near the flat weak budget, not tens of seconds.
      expect(weak.inMilliseconds,
          lessThanOrEqualTo(thinkTimeForLevel(0).inMilliseconds + 50));
    });

    test('most of the increment is available each move', () {
      // With a healthy clock and a 10s increment, the budget reflects it.
      final noInc = _budget(const Duration(minutes: 5), 0, 20);
      final withInc = _budget(const Duration(minutes: 5), 10, 20);
      expect(withInc, greaterThan(noInc));
    });

    test('almost out of time: move essentially instantly, never negative', () {
      final b = _budget(const Duration(milliseconds: 300), 0, 20);
      expect(b.inMilliseconds, greaterThanOrEqualTo(50));
      expect(b, lessThan(const Duration(milliseconds: 300)));
    });

    test('zero/expired clock returns a tiny positive budget', () {
      expect(_budget(Duration.zero, 0, 20).inMilliseconds, 50);
    });

    test('strength scales monotonically with the clock', () {
      final rem = const Duration(minutes: 5);
      var prev = -1;
      for (final level in [0, 5, 10, 15, 20]) {
        final ms = _budget(rem, 0, level).inMilliseconds;
        expect(ms, greaterThanOrEqualTo(prev),
            reason: 'level $level should not think less than a weaker level');
        prev = ms;
      }
    });
  });
}
