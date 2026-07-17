// Regression tests for the reported symptom: the built-in engine appearing to
// "hang after a few moves" on a tablet.
//
// It was never an infinite hang — bestMove ran a fixed-depth search (up to
// depth 10 at high skill) in a compute() isolate that ignored moveTime and
// could not be stopped. As the position opened up that took 10-25s per move on
// an iPad. Play is now driven by a level-scaled time budget instead.
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desktop CI is much faster than a tablet, but the budget is wall-clock, so a
/// generous multiple of it still catches a return to unbounded fixed-depth
/// search (which took tens of seconds).
Duration _ceilingFor(int skill) => thinkTimeForLevel(skill) * 4;

void main() {
  group('think time budget', () {
    test('scales with level and stays within sane bounds', () {
      expect(thinkTimeForLevel(0), const Duration(milliseconds: 200));
      expect(thinkTimeForLevel(10), const Duration(milliseconds: 1100));
      expect(thinkTimeForLevel(20), const Duration(milliseconds: 2000));
      // Out-of-range levels must not produce absurd budgets.
      expect(thinkTimeForLevel(-5), const Duration(milliseconds: 200));
      expect(thinkTimeForLevel(99), const Duration(milliseconds: 2000));
    });
  });

  group('uciGoCommand', () {
    test('drives play by movetime, not a fixed depth', () {
      // The old `go depth 15` is why Stockfish was slow even at low levels:
      // Skill Level caps strength, not search time.
      expect(uciGoCommand(skillLevel: 7), 'go movetime 830');
      expect(uciGoCommand(skillLevel: 20), 'go movetime 2000');
    });

    test('honours an explicit moveTime', () {
      expect(uciGoCommand(moveTime: const Duration(seconds: 3)),
          'go movetime 3000');
    });

    test('still supports explicit depth for hints/analysis', () {
      expect(uciGoCommand(depth: 12), 'go depth 12');
      // Depth wins over a budget when explicitly requested.
      expect(uciGoCommand(depth: 12, moveTime: const Duration(seconds: 3)),
          'go depth 12');
    });
  });

  group('DartEngine latency', () {
    test('successive moves at max skill each return within budget', () async {
      // The reported symptom: fine at first, then "hangs" a few moves in as the
      // position opens up. Max skill previously meant a fixed depth-10 search.
      const skill = 20;
      final engine = DartEngine();
      await engine.initialize();
      addTearDown(engine.dispose);

      final game = chess.Chess();
      final played = <String>[];

      for (var i = 0; i < 8; i++) {
        final position = played.isEmpty
            ? 'position startpos'
            : 'position startpos moves ${played.join(' ')}';

        final legal = game
            .generate_moves()
            .map((m) =>
                '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}')
            .toSet();

        final sw = Stopwatch()..start();
        final move = await engine.bestMove(position, skillLevel: skill);
        sw.stop();

        expect(legal, contains(move),
            reason: 'move ${i + 1} ($move) is not legal in ${game.fen}');
        expect(sw.elapsed, lessThan(_ceilingFor(skill)),
            reason: 'move ${i + 1} took ${sw.elapsedMilliseconds}ms — '
                'the search is no longer bounded by its time budget');

        game.move({
          'from': move.substring(0, 2),
          'to': move.substring(2, 4),
          'promotion': move.length > 4 ? move.substring(4, 5) : null,
        });
        played.add(move);
      }
    });

    test('an explicit deep request is still time-capped', () async {
      // depth 12 unbounded would run for minutes.
      final engine = DartEngine();
      await engine.initialize();
      addTearDown(engine.dispose);

      final sw = Stopwatch()..start();
      final move = await engine.bestMove('position startpos', depth: 12);
      sw.stop();

      expect(move.length, greaterThanOrEqualTo(4));
      expect(sw.elapsed, lessThan(kFixedDepthTimeCap * 3),
          reason: 'fixed-depth requests must honour kFixedDepthTimeCap');
    });
  });
}
