import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/chess_game.dart';

void main() {
  group('ChessGame legal move caching', () {
    test('getLegalMoves returns consistent results without moves', () {
      final game = ChessGame();
      final moves1 = game.getLegalMoves();
      final moves2 = game.getLegalMoves();

      // Should return the same list instance (cached)
      expect(identical(moves1, moves2), isTrue);
      // Should have the standard 20 opening moves
      expect(moves1.length, 20);
    });

    test('getLegalMoves cache invalidated after makeMove', () {
      final game = ChessGame();
      final movesBefore = game.getLegalMoves();
      expect(movesBefore.length, 20);

      // Make a move
      final success = game.makeMove('e2e4');
      expect(success, isTrue);

      // After move, cache should be invalidated and new moves computed
      final movesAfter = game.getLegalMoves();
      expect(identical(movesBefore, movesAfter), isFalse);
      // Black should also have 20 opening moves
      expect(movesAfter.length, 20);
    });

    test('getLegalMoves cache invalidated after undoMove', () {
      final game = ChessGame();
      game.makeMove('e2e4');
      final movesAfterE4 = game.getLegalMoves();

      game.undoMove();
      final movesAfterUndo = game.getLegalMoves();

      expect(identical(movesAfterE4, movesAfterUndo), isFalse);
      // Should be back to initial 20 moves
      expect(movesAfterUndo.length, 20);
    });

    test('getLegalMoves cache invalidated after reset', () {
      final game = ChessGame();
      game.makeMove('e2e4');
      game.makeMove('e7e5');
      final movesBeforeReset = game.getLegalMoves();

      game.reset();
      final movesAfterReset = game.getLegalMoves();

      expect(identical(movesBeforeReset, movesAfterReset), isFalse);
      expect(movesAfterReset.length, 20);
    });
  });

  group('ChessGame move validation', () {
    test('makeMove returns false for illegal move', () {
      final game = ChessGame();
      // Try to move a pawn 3 squares forward (illegal)
      final result = game.makeMove('e2e5');
      expect(result, isFalse);
      // Try to move to an occupied square of same color
      final result2 = game.makeMove('e1e2');
      expect(result2, isFalse);
      // Try a completely invalid square
      final result3 = game.makeMove('z9z8');
      expect(result3, isFalse);
      // Too short
      final result4 = game.makeMove('e2');
      expect(result4, isFalse);
    });

    test('makeMove handles pawn promotion', () {
      final game = ChessGame();
      // Set up a position where promotion is possible by playing
      // moves to get a pawn to the 7th rank. Use a known sequence:
      // We'll use a simpler approach: make moves to enable promotion
      // a2a4, b7b5, a4b5 (capture), ... this takes too many moves.
      // Instead, let's just test the promotion suffix parsing:
      // Play enough moves to promote. Use a crafted sequence:
      game.makeMove('b2b4');
      game.makeMove('a7a5');
      game.makeMove('b4a5'); // capture
      game.makeMove('b7b6');
      game.makeMove('a5b6'); // capture
      game.makeMove('c7c6');
      game.makeMove('b6b7'); // pawn on 7th rank
      game.makeMove('c6c5');
      // Promote by capturing rook on a8
      final result = game.makeMove('b7a8q');
      expect(result, isTrue);
      final board = game.board;
      expect(board[0][0]!.type, PieceType.queen);
      expect(board[0][0]!.color, PieceColor.white);
    });

    test('isGameOver detects checkmate', () {
      final game = ChessGame();
      // Scholar's mate: e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7
      expect(game.makeMove('e2e4'), isTrue);
      expect(game.makeMove('e7e5'), isTrue);
      expect(game.makeMove('d1h5'), isTrue);
      expect(game.makeMove('b8c6'), isTrue);
      expect(game.makeMove('f1c4'), isTrue);
      expect(game.makeMove('g8f6'), isTrue);
      expect(game.makeMove('h5f7'), isTrue);
      expect(game.isGameOver, isTrue);
    });

    test('gameOverReason returns Checkmate', () {
      final game = ChessGame();
      // Scholar's mate
      game.makeMove('e2e4');
      game.makeMove('e7e5');
      game.makeMove('d1h5');
      game.makeMove('b8c6');
      game.makeMove('f1c4');
      game.makeMove('g8f6');
      game.makeMove('h5f7');
      expect(game.gameOverReason, 'Checkmate');
    });

    test('winner returns correct side', () {
      final game = ChessGame();
      // Scholar's mate - White wins
      game.makeMove('e2e4');
      game.makeMove('e7e5');
      game.makeMove('d1h5');
      game.makeMove('b8c6');
      game.makeMove('f1c4');
      game.makeMove('g8f6');
      game.makeMove('h5f7');
      expect(game.winner, 'White');
    });

    test('winner returns null when no checkmate', () {
      final game = ChessGame();
      expect(game.winner, isNull);
      game.makeMove('e2e4');
      expect(game.winner, isNull);
    });
  });

  group('ChessGame position and history', () {
    test('positionCommand builds correct UCI string', () {
      final game = ChessGame();
      expect(game.positionCommand, 'position startpos');

      game.makeMove('e2e4');
      expect(game.positionCommand, 'position startpos moves e2e4');

      game.makeMove('e7e5');
      expect(game.positionCommand, 'position startpos moves e2e4 e7e5');
    });

    test('moveHistory tracks all moves', () {
      final game = ChessGame();
      expect(game.moveHistory, isEmpty);

      game.makeMove('e2e4');
      expect(game.moveHistory, ['e2e4']);

      game.makeMove('e7e5');
      expect(game.moveHistory, ['e2e4', 'e7e5']);

      game.makeMove('g1f3');
      expect(game.moveHistory, ['e2e4', 'e7e5', 'g1f3']);
    });

    test('annotations list grows with moves', () {
      final game = ChessGame();
      expect(game.annotations, isEmpty);
      expect(game.lastAnnotation, isNull);

      game.makeMove('e2e4');
      expect(game.annotations.length, 1);
      expect(game.lastAnnotation, isNotNull);
      expect(game.lastAnnotation!.move, 'e2e4');

      game.makeMove('e7e5');
      expect(game.annotations.length, 2);
      expect(game.lastAnnotation!.move, 'e7e5');
    });

    test('inCheck detects check', () {
      final game = ChessGame();
      // Set up a position where the king is in check
      // Use Fool's check: e2e4 f7f6 d2d4 g7g5 d1h5 (check to black king)
      // Actually Qh5+ is check to black: after 1.e4 f6 2.d4 g5 3.Qh5+
      game.makeMove('e2e4');
      game.makeMove('f7f6');
      game.makeMove('d2d4');
      game.makeMove('g7g5');
      game.makeMove('d1h5');
      // Now black is in check
      expect(game.inCheck, isTrue);
    });

    test('getLegalMoves returns valid UCI moves from starting position', () {
      final game = ChessGame();
      final moves = game.getLegalMoves();
      // Check common opening moves are present
      expect(moves, contains('e2e3'));
      expect(moves, contains('e2e4'));
      expect(moves, contains('d2d3'));
      expect(moves, contains('d2d4'));
      expect(moves, contains('g1f3'));
      expect(moves, contains('g1h3'));
      expect(moves, contains('b1c3'));
      expect(moves, contains('b1a3'));
      // Verify all 20 standard opening moves
      expect(moves.length, 20);
    });

    test('board getter caches results', () {
      final game = ChessGame();
      final board1 = game.board;
      final board2 = game.board;
      // Should return the exact same list instance (cached)
      expect(identical(board1, board2), isTrue);
    });

    test('board getter returns correct initial position', () {
      final game = ChessGame();
      final board = game.board;
      // White rook at a1 = board[7][0]
      expect(board[7][0]!.type, PieceType.rook);
      expect(board[7][0]!.color, PieceColor.white);
      // Black king at e8 = board[0][4]
      expect(board[0][4]!.type, PieceType.king);
      expect(board[0][4]!.color, PieceColor.black);
      // Empty square at e4 = board[4][4]
      expect(board[4][4], isNull);
    });

    test('squareToAlgebraic converts correctly', () {
      final game = ChessGame();
      expect(game.squareToAlgebraic(0, 0), 'a8');
      expect(game.squareToAlgebraic(7, 0), 'a1');
      expect(game.squareToAlgebraic(7, 7), 'h1');
      expect(game.squareToAlgebraic(0, 4), 'e8');
      expect(game.squareToAlgebraic(6, 4), 'e2');
    });
  });
}
