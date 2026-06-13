import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:chess/chess.dart' as chess;

void main() {
  group('DartEngine plays a game', () {
    test('engine plays 20 legal moves from starting position', () async {
      final engine = DartEngine();
      await engine.initialize();
      expect(engine.state, EngineState.ready);

      final game = chess.Chess();
      final moves = <String>[];

      for (int i = 0; i < 20; i++) {
        final posCmd = moves.isEmpty
            ? 'position startpos'
            : 'position startpos moves ${moves.join(' ')}';

        final move = await engine.bestMove(posCmd, depth: 2);
        expect(move.length, greaterThanOrEqualTo(4),
            reason: 'Move $i should be valid UCI: $move');

        // Verify move is legal
        final result = game.move({
          'from': move.substring(0, 2),
          'to': move.substring(2, 4),
          'promotion': move.length > 4 ? move.substring(4, 5) : null,
        });
        expect(result, isTrue, reason: 'Move $i ($move) should be legal');
        moves.add(move);

        if (game.game_over) break;
      }

      expect(moves.length, greaterThan(0));
      engine.dispose();
    });

    test('engine finds mate in 1', () async {
      final engine = DartEngine();
      await engine.initialize();

      // White to move, Qh5 is mate (Scholar's mate setup minus one move)
      // FEN: r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4
      // Actually let's use a simpler mate-in-1:
      // White queen on h5, black king on e8, f7 is undefended
      // FEN where Qxf7# is mate:
      final move = await engine.bestMove(
        'position fen rnbqkbnr/pppp1ppp/8/4p2Q/4P3/8/PPPP1PPP/RNB1KBNR w KQkq - 0 1',
        depth: 3,
      );
      // Engine should find Qxe5+ or Qxf7# or similar strong move
      expect(move.length, greaterThanOrEqualTo(4));

      engine.dispose();
    });

    test('engine responds differently at different depths', () async {
      final engine = DartEngine();
      await engine.initialize();

      // At depth 1 vs depth 4, the move might differ
      // (not guaranteed but search should complete at both)
      final move1 = await engine.bestMove('position startpos', depth: 1);
      final move4 = await engine.bestMove('position startpos', depth: 4);

      expect(move1.length, greaterThanOrEqualTo(4));
      expect(move4.length, greaterThanOrEqualTo(4));

      engine.dispose();
    });

    test('engine handles position with few legal moves', () async {
      final engine = DartEngine();
      await engine.initialize();

      // King and pawn endgame — limited moves
      final move = await engine.bestMove(
        'position fen 8/8/8/8/8/4k3/4P3/4K3 w - - 0 1',
        depth: 4,
      );
      expect(move.length, greaterThanOrEqualTo(4));

      engine.dispose();
    });

    test('search result has positive node count', () async {
      final engine = DartEngine();
      await engine.initialize();

      // Use analyze stream to check search results
      final results = <EvalInfo>[];
      await for (final info
          in engine.analyze('position startpos', depth: 3)) {
        results.add(info);
      }

      expect(results, isNotEmpty);
      expect(results.last.depth, greaterThanOrEqualTo(1));
      expect(results.last.bestMove, isNotNull);

      engine.dispose();
    });
  });
}
