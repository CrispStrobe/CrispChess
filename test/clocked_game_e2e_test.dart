// End-to-end: play a full clocked engine-vs-engine game through the *real* app
// stack — EngineService + the bitboard DartEngine + ChessClock + clock-aware
// time management — and assert the whole integration behaves:
//   * every engine move is legal,
//   * each move returns within its clock-derived budget (+ overhead),
//   * the clock is never flagged (time stays positive),
//   * the game reaches a natural end or the ply cap cleanly.
import 'dart:async';

import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/chess_clock.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/services/engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full clocked engine-vs-engine game via the real services', () async {
    const level = 14;
    // A short clock keeps the test quick while still exercising real budgeting.
    final clock = ChessClock(
      timeControl: TimeControl.custom,
      customBaseTime: const Duration(seconds: 20),
      customIncrementSeconds: 0,
    );

    final service = EngineService(DartEngine());
    await service.initialize();
    addTearDown(service.dispose);

    final board = chess.Chess();
    final playedMoves = <String>[];
    var plies = 0;
    var ended = false;

    for (; plies < 60; plies++) {
      // Terminal?
      if (board.game_over) {
        ended = true;
        break;
      }

      final side = board.turn == chess.Color.WHITE ? clock.white : clock.black;
      final legalBefore = board
          .generate_moves()
          .map((m) =>
              '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}')
          .toSet();

      final budget = clockAwareThinkTime(
        remaining: side.remaining,
        incrementSeconds: clock.incrementSeconds,
        skillLevel: level,
      );

      final position = playedMoves.isEmpty
          ? 'position startpos'
          : 'position startpos moves ${playedMoves.join(' ')}';

      final done = Completer<String>();
      final sub = service.events.listen((e) {
        if (e is BestMoveEvent && !done.isCompleted) done.complete(e.move);
        if (e is EngineErrorEvent && !done.isCompleted) {
          done.completeError(StateError('engine error at ply $plies'));
        }
      });

      final sw = Stopwatch()..start();
      await service.requestMove(position, skillLevel: level, moveTime: budget);
      final move = await done.future.timeout(const Duration(seconds: 20));
      sw.stop();
      await sub.cancel();

      // Move is legal for the side to move.
      expect(legalBefore, contains(move),
          reason: 'ply $plies: $move illegal in ${board.fen}');

      // Returned within budget + overhead (isolate spawn, book, CI slack).
      // Opening-book moves are near-instant, so this only really bites on real
      // searches — which must honour the budget.
      expect(sw.elapsedMilliseconds, lessThan(budget.inMilliseconds + 3000),
          reason: 'ply $plies took ${sw.elapsedMilliseconds}ms for a '
              '${budget.inMilliseconds}ms budget');

      // Clock bookkeeping: time ticks down during the think, increment on move.
      side.remaining -= sw.elapsed;
      side.remaining += Duration(seconds: clock.incrementSeconds);
      expect(side.remaining, greaterThan(Duration.zero),
          reason: 'engine flagged its own clock at ply $plies');

      board.move({
        'from': move.substring(0, 2),
        'to': move.substring(2, 4),
        'promotion': move.length > 4 ? move.substring(4, 5) : null,
      });
      playedMoves.add(move);
    }

    // Either the game ended naturally or it ran the full ply cap — both are a
    // clean completion (the point is that nothing flagged, hung, or went
    // illegal along the way).
    expect(plies > 0, isTrue);
    print('played $plies plies (${ended ? "game over" : "ply cap"}); '
        'white left ${clock.white.remaining.inMilliseconds}ms, '
        'black left ${clock.black.remaining.inMilliseconds}ms');
    print('moves: ${playedMoves.join(' ')}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
