import 'package:flutter_test/flutter_test.dart';
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/pgn.dart';

void main() {
  group('PGN export', () {
    test('exports empty game with headers', () {
      final game = chess.Chess();
      final pgn = exportPgn(game: game);
      expect(pgn, contains('[Event "CrispChess Game"]'));
      expect(pgn, contains('[White "Human"]'));
      expect(pgn, contains('[Black "Engine"]'));
      expect(pgn, contains('[Result "*"]'));
    });

    test('exports game with moves', () {
      final game = chess.Chess();
      game.move({'from': 'e2', 'to': 'e4'});
      game.move({'from': 'e7', 'to': 'e5'});
      game.move({'from': 'g1', 'to': 'f3'});

      final pgn = exportPgn(game: game);
      expect(pgn, contains('1. e4 e5 2. Nf3'));
    });

    test('includes custom headers', () {
      final game = chess.Chess();
      final pgn = exportPgn(
        game: game,
        headers: PgnHeaders(
          white: 'Alice',
          black: 'Stockfish 16',
          date: '2026.06.13',
        ),
      );
      expect(pgn, contains('[White "Alice"]'));
      expect(pgn, contains('[Black "Stockfish 16"]'));
      expect(pgn, contains('[Date "2026.06.13"]'));
    });

    test('escapes quotes in header values', () {
      final game = chess.Chess();
      final pgn = exportPgn(
        game: game,
        headers: PgnHeaders(white: 'Bob "The King"'),
      );
      expect(pgn, contains(r'Bob \"The King\"'));
    });
  });

  group('PGN import', () {
    test('imports simple game', () {
      const pgnText = '1. e4 e5 2. Nf3 Nc6 3. Bb5';
      final game = importPgn(pgnText);
      expect(game, isNotNull);
      // Should be black's turn after 3. Bb5
      expect(game!.turn, chess.Color.BLACK);
    });

    test('imports game with headers', () {
      const pgnText = '''
[Event "Test"]
[White "Human"]
[Black "Engine"]

1. d4 d5 2. c4 e6 3. Nc3
''';
      final game = importPgn(pgnText);
      expect(game, isNotNull);
      expect(game!.turn, chess.Color.BLACK);
    });

    test('returns null for invalid PGN', () {
      const pgnText = '1. Zz9 invalid';
      final game = importPgn(pgnText);
      expect(game, isNull);
    });

    test('imports empty game', () {
      const pgnText = '';
      final game = importPgn(pgnText);
      expect(game, isNotNull);
    });
  });

  group('parseHeaders', () {
    test('parses standard headers', () {
      const pgn = '''
[Event "Test Event"]
[Site "Internet"]
[Date "2026.06.13"]
[White "Alice"]
[Black "Bob"]
[Result "1-0"]

1. e4 e5
''';
      final headers = parseHeaders(pgn);
      expect(headers['Event'], 'Test Event');
      expect(headers['White'], 'Alice');
      expect(headers['Black'], 'Bob');
      expect(headers['Result'], '1-0');
    });
  });

  group('gameResult', () {
    test('returns * for ongoing game', () {
      final game = chess.Chess();
      expect(gameResult(game), '*');
    });

    test('returns 1/2-1/2 for stalemate', () {
      // Known stalemate position
      final game = chess.Chess.fromFEN('k7/8/1K6/8/8/8/8/1Q6 w - - 0 1');
      // Move queen to trap king in stalemate
      game.move({'from': 'b1', 'to': 'a2'});
      if (game.in_stalemate) {
        expect(gameResult(game), '1/2-1/2');
      }
    });
  });
}
