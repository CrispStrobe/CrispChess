// An engine must always answer with a legal move when one exists, however
// little time it is given.
//
// Found by the engine-vs-engine gate at a 60ms budget: `bestMove` came back
// with `Bad state: No legal moves` from the *starting position*. A budget too
// small to finish depth 1 — and a cold `compute()` isolate can spend tens of
// milliseconds before the search even begins — left the search with no result,
// and that was reported as though the position had none. For the caller it is
// unrecoverable: the game stops with an error that says something false about
// the board.
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/dart_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> _legalMoves(String fen) => {
      for (final m in chess.Chess.fromFEN(fen).generate_moves())
        '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
    };

void main() {
  group('DartEngine with a budget too small to search', () {
    late DartEngine engine;

    setUp(() async {
      engine = DartEngine();
      await engine.initialize();
    });
    tearDown(() => engine.dispose());

    for (final ms in [1, 10, 60]) {
      test('still returns a legal move at ${ms}ms', () async {
        final move = await engine.bestMove(
          'position startpos',
          moveTime: Duration(milliseconds: ms),
          skillLevel: 20,
        );
        expect(
            _legalMoves('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
            contains(move));
      });
    }

    test('still returns a legal move mid-game', () async {
      const moves = 'e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6';
      final board = chess.Chess();
      for (final uci in moves.split(' ')) {
        board.move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
      }
      final move = await engine.bestMove(
        'position startpos moves $moves',
        moveTime: const Duration(milliseconds: 5),
        skillLevel: 20,
      );
      expect(_legalMoves(board.fen), contains(move));
    });

    test('a real checkmate still reports having no move', () async {
      // The message was not wrong in principle, only in when it appeared.
      const mated = '7k/5QQ1/8/8/8/8/8/7K b - - 0 1';
      expect(_legalMoves(mated), isEmpty);
      await expectLater(
        engine.bestMove('position fen $mated',
            moveTime: const Duration(milliseconds: 200)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
