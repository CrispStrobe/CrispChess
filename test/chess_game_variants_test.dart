import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/chess/game_state.dart' show ChessVariant;

void main() {
  group('ChessGame variants', () {
    test('defaults to standard variant', () {
      final game = ChessGame();
      expect(game.variant, ChessVariant.standard);
    });

    test('check counters start at zero', () {
      final game = ChessGame();
      expect(game.whiteChecks, 0);
      expect(game.blackChecks, 0);
    });

    test('reset clears check counters', () {
      final game = ChessGame();
      game.whiteChecks = 5;
      game.blackChecks = 3;
      game.reset();
      expect(game.whiteChecks, 0);
      expect(game.blackChecks, 0);
    });

    test('loadFen clears check counters', () {
      final game = ChessGame();
      game.whiteChecks = 2;
      game.blackChecks = 1;
      game.loadFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
      expect(game.whiteChecks, 0);
      expect(game.blackChecks, 0);
    });

    test('KOTH: isGameOver when king reaches center', () {
      final game = ChessGame();
      game.variant = ChessVariant.kingOfTheHill;
      // White king on e4 with pieces to avoid insufficient material
      // Rook on a1 doesn't check the black king on h8
      game.loadFen('7k/8/8/8/4K3/8/8/R7 w - - 0 1');
      expect(game.isGameOver, isTrue);
      expect(game.gameOverReason, 'King of the Hill');
      expect(game.winner, 'White');
    });

    test('KOTH: not game over when king is not on center', () {
      final game = ChessGame();
      game.variant = ChessVariant.kingOfTheHill;
      // King on e3 (not center), with rook to avoid insufficient material
      game.loadFen('7k/8/8/8/8/4K3/8/R7 w - - 0 1');
      expect(game.isGameOver, isFalse);
    });

    test('three-check: game over at 3 checks', () {
      final game = ChessGame();
      game.variant = ChessVariant.threeCheck;
      game.whiteChecks = 3;
      expect(game.isGameOver, isTrue);
      expect(game.gameOverReason, 'Three-check');
      expect(game.winner, 'White');
    });

    test('three-check: not game over below 3 checks', () {
      final game = ChessGame();
      game.variant = ChessVariant.threeCheck;
      game.whiteChecks = 2;
      game.blackChecks = 2;
      expect(game.isGameOver, isFalse);
    });

    test('standard variant ignores KOTH center squares', () {
      final game = ChessGame();
      game.variant = ChessVariant.standard;
      game.loadFen('8/8/8/8/4K3/8/8/4k3 w - - 0 1');
      // King on e4 but variant is standard — should not trigger KOTH
      expect(game.gameOverReason, isNot('King of the Hill'));
    });

    test('variant can be changed', () {
      final game = ChessGame();
      game.variant = ChessVariant.chess960;
      expect(game.variant, ChessVariant.chess960);
      game.variant = ChessVariant.threeCheck;
      expect(game.variant, ChessVariant.threeCheck);
    });
  });
}
