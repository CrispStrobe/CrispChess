// PGN export is driven by the game tree, not by `chess.Chess`.
//
// Regression: `undoMove` reloads the board from a FEN, and `chess.Chess.load`
// clears that object's move history — so exporting after any takeback produced
// a PGN with headers and no moves at all. The tree also knows the real starting
// position, which a game that began from a FEN needs in order to be readable.
import 'package:crispchess/chess/chess_game.dart';
import 'package:flutter_test/flutter_test.dart';

String _moveText(String pgn) {
  final lines = pgn.split('\n');
  final body = lines.where((l) => !l.trim().startsWith('[')).join(' ');
  return body.replaceAll(RegExp(r'\s+'), ' ').trim();
}

ChessGame _gameWith(List<String> moves) {
  final game = ChessGame();
  for (final m in moves) {
    expect(game.makeMove(m), isTrue, reason: 'could not play $m');
  }
  return game;
}

void main() {
  group('ChessGame.toPgn', () {
    test('writes the moves played', () {
      final game = _gameWith(['e2e4', 'e7e5', 'g1f3', 'b8c6']);
      expect(_moveText(game.toPgn()), '1. e4 e5 2. Nf3 Nc6 *');
    });

    test('still writes the moves after a takeback', () {
      final game = _gameWith(['e2e4', 'e7e5', 'g1f3', 'b8c6']);
      game.undoMove();
      game.undoMove();
      expect(_moveText(game.toPgn()), '1. e4 e5 *',
          reason: 'export must follow the board, and an undone move is not '
              'part of the game any more');
    });

    test('records the starting position when it is not the initial one', () {
      const fen = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';
      final game = ChessGame();
      expect(game.loadFen(fen), isTrue);
      expect(game.makeMove('e2e4'), isTrue);

      final pgn = game.toPgn();
      expect(pgn, contains('[SetUp "1"]'));
      expect(pgn, contains('[FEN "$fen"]'));
      expect(_moveText(pgn), '1. e4 *');
    });

    test('continues the move numbering of a mid-game FEN', () {
      const fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 3 3';
      final game = ChessGame();
      expect(game.loadFen(fen), isTrue);
      expect(game.makeMove('g8f6'), isTrue);
      expect(game.makeMove('b1c3'), isTrue);
      expect(_moveText(game.toPgn()), '3... Nf6 4. Nc3 *');
    });

    test('writes a sideline as a RAV variation', () {
      final game = _gameWith(['e2e4', 'e7e5']);
      // Take back black's reply and try something else — the first move stays
      // in the tree as a sibling of the new one.
      game.undoMove();
      expect(game.makeMove('c7c5'), isTrue);

      final text = _moveText(game.toPgn());
      expect(text, startsWith('1. e4 c5'));
      expect(text, contains('(1... e5'));
    });

    test('names the players from the engine and side', () {
      final game = _gameWith(['e2e4']);
      final asWhite = game.toPgn(engineName: 'Lynx');
      expect(asWhite, contains('[White "Human"]'));
      expect(asWhite, contains('[Black "Lynx"]'));

      final asBlack = game.toPgn(engineName: 'Lynx', playAsBlack: true);
      expect(asBlack, contains('[White "Lynx"]'));
      expect(asBlack, contains('[Black "Human"]'));
    });

    test('round-trips through the importer', () {
      final game = _gameWith(['d2d4', 'd7d5', 'c2c4', 'e7e6', 'b1c3']);
      final pgn = game.toPgn();

      final reloaded = ChessGame();
      expect(reloaded.loadPgn(pgn), isTrue);
      expect(reloaded.moveHistory, game.moveHistory);
      expect(reloaded.moveHistorySan, game.moveHistorySan);
      expect(reloaded.currentFEN, game.currentFEN);
    });
  });
}
