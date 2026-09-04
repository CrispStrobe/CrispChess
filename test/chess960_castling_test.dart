// Chess960 castling, which `package:chess` cannot generate.
//
// The library hardcodes the standard geometry — king on e1/e8 moving two
// squares — so in a shuffled position it produces no castling move at all and
// ignores the KQkq rights in the FEN. Verified before this was written: from
// `nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/NRKBBQRN w KQkq - 0 1` it generated 18
// moves, none of them a king move. The app offers Chess960, so a player who
// drew a position with the king on c1 could never castle.
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/chess960_castling.dart';
import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/chess/game_state.dart' show ChessVariant;
import 'package:flutter_test/flutter_test.dart';

/// King c1, rooks b1 and g1 — nothing on a standard square.
const _shuffled = 'nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/NRKBBQRN w KQkq - 0 1';

ChessGame _game960(String fen) {
  final game = ChessGame();
  game.variant = ChessVariant.chess960;
  expect(game.loadFen(fen), isTrue);
  return game;
}

void main() {
  group('generation', () {
    test('the library really does offer none', () {
      final moves = chess.Chess.fromFEN(_shuffled)
          .generate_moves()
          .map((m) => '${m.fromAlgebraic}${m.toAlgebraic}');
      expect(moves.where((m) => m.startsWith('c1')), isEmpty,
          reason: 'this is the gap being filled; if the library gained '
              'Chess960 castling, this shim should go');
    });

    test('offers both sides when the back rank is clear', () {
      // Same layout, minor pieces lifted so the king and rooks can move.
      final castles = chess960Castles(
          chess.Chess.fromFEN('nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w KQ - 0 1'));
      expect(castles.map((c) => c.uci), containsAll(['c1g1', 'c1c1']));
    });

    test('a piece in the way blocks it', () {
      // Knight on f1 sits between the king and its g1 destination.
      final castles = chess960Castles(
          chess.Chess.fromFEN('nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/1RK2NR1 w KQ - 0 1'));
      expect(castles.map((c) => c.kingside), isNot(contains(true)));
    });

    test('no rights, no castling', () {
      final castles = chess960Castles(
          chess.Chess.fromFEN('nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w - - 0 1'));
      expect(castles, isEmpty);
    });

    test('a standard position is left to the library', () {
      // Otherwise the move would be offered twice.
      expect(
          chess960Castles(chess.Chess.fromFEN(
              'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1')),
          isEmpty);
    });

    test('a king that would cross an attacked square cannot castle', () {
      // Black rook on f8 with the f-file open (no f7, no f2 pawn) covers f1,
      // which the white king must cross going c1 to g1. Queenside is still
      // legal, so this is specifically about the path.
      final castles = chess960Castles(chess.Chess.fromFEN(
          '1rk2r2/ppppp1pp/8/8/8/8/PPPPP1PP/1RK3R1 w KQ - 0 1'));
      expect(castles.map((c) => c.kingside), isNot(contains(true)));
      expect(castles.map((c) => c.kingside), contains(false));
    });

    test('a king in check cannot castle', () {
      // Black rook on c8 down an open c-file, white king on c1.
      final castles = chess960Castles(chess.Chess.fromFEN(
          '2rk4/pp1ppppp/8/8/8/8/PP1PPPPP/1RK3R1 w KQ - 0 1'));
      expect(castles, isEmpty);
    });
  });

  group('playing it', () {
    test('kingside puts the king on g1 and the rook on f1', () {
      final game = _game960('nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w KQ - 0 1');
      expect(game.getLegalMoves(), contains('c1g1'));
      expect(game.makeMove('c1g1'), isTrue);

      final placement = game.currentFEN.split(' ').first.split('/').last;
      expect(placement, '1R3RK1');
      expect(game.currentFEN.split(' ')[1], 'b', reason: 'turn must pass');
      expect(game.currentFEN.split(' ')[2], isNot(contains('K')),
          reason: 'white loses both rights by castling');
      expect(game.moveHistorySan, ['O-O']);
      expect(game.moveHistory, ['c1g1']);
    });

    test('queenside puts the king on c1 and the rook on d1', () {
      final game = _game960('nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w KQ - 0 1');
      expect(game.makeMove('c1c1'), isTrue);
      final placement = game.currentFEN.split(' ').first.split('/').last;
      expect(placement, '2KR2R1');
      expect(game.moveHistorySan, ['O-O-O']);
    });

    test('the king-takes-rook form is accepted too', () {
      // What an engine running with UCI_Chess960 may answer.
      final game = _game960('nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w KQ - 0 1');
      expect(game.makeMove('c1g1'), isTrue, reason: 'king-to-destination');

      final other = _game960('nrkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w KQ - 0 1');
      expect(other.makeMove('c1b1'), isTrue, reason: 'king-takes-rook');
      expect(other.currentFEN.split(' ').first.split('/').last, '2KR2R1');
    });

    test('black castles too', () {
      final game = _game960('1rk3r1/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 b kq - 0 1');
      expect(game.makeMove('c8g8'), isTrue);
      expect(game.currentFEN.split(' ').first.split('/').first, '1r3rk1');
      expect(game.currentFEN.split(' ')[5], '2',
          reason: 'black completing a move advances the full-move number');
    });

    test('it is refused outside Chess960', () {
      // The standard game must not gain a second way to castle.
      final game = ChessGame();
      expect(game.loadFen('1rk3r1/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w KQ - 0 1'),
          isTrue);
      expect(game.makeMove('c1g1'), isFalse);
    });

    test('the game continues normally afterwards', () {
      final game = _game960('1rk3r1/pppppppp/8/8/8/8/PPPPPPPP/1RK3R1 w KQkq - 0 1');
      expect(game.makeMove('c1g1'), isTrue);
      expect(game.makeMove('c8g8'), isTrue, reason: 'black castles in reply');
      expect(game.makeMove('e2e4'), isTrue, reason: 'and play carries on');
      expect(game.moveHistorySan, ['O-O', 'O-O', 'e4']);
      expect(game.positionCommand, contains('moves c1g1 c8g8 e2e4'));
    });
  });
}
