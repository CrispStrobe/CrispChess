import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/opening_book.dart';

void main() {
  group('OpeningBook', () {
    test('returns moves for starting position', () {
      const startFen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final moves = OpeningBook.lookup(startFen);
      expect(moves, isNotNull);
      expect(moves!.length, greaterThan(3));
      // e2e4 and d2d4 should be among the moves
      final ucis = moves.map((m) => m.uci).toList();
      expect(ucis, contains('e2e4'));
      expect(ucis, contains('d2d4'));
    });

    test('returns moves after 1.e4', () {
      const fen =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      final moves = OpeningBook.lookup(fen);
      expect(moves, isNotNull);
      final ucis = moves!.map((m) => m.uci).toList();
      expect(ucis, contains('e7e5')); // Open game
      expect(ucis, contains('c7c5')); // Sicilian
    });

    test('returns null for unknown position', () {
      const randomFen = '8/8/8/4k3/8/8/4K3/8 w - - 0 50';
      expect(OpeningBook.lookup(randomFen), isNull);
    });

    test('pickMove returns a valid UCI string for known position', () {
      const startFen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final move = OpeningBook.pickMove(startFen);
      expect(move, isNotNull);
      expect(move!.length, greaterThanOrEqualTo(4));
    });

    test('pickMove returns null for unknown position', () {
      const randomFen = '8/8/8/4k3/8/8/4K3/8 w - - 0 50';
      expect(OpeningBook.pickMove(randomFen), isNull);
    });

    test('position key ignores castling and en passant', () {
      // Same position, different castling/EP/move counters
      const fen1 =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      const fen2 =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b - - 0 1';
      final moves1 = OpeningBook.lookup(fen1);
      final moves2 = OpeningBook.lookup(fen2);
      expect(moves1, isNotNull);
      expect(moves2, isNotNull);
      expect(moves1!.length, moves2!.length);
    });

    test('all book moves have reasonable format', () {
      const startFen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final moves = OpeningBook.lookup(startFen)!;
      for (final m in moves) {
        expect(m.uci.length, greaterThanOrEqualTo(4));
        expect(m.weight, greaterThan(0));
        // Squares should be valid (a-h, 1-8)
        expect(m.uci[0], matches(RegExp(r'[a-h]')));
        expect(m.uci[1], matches(RegExp(r'[1-8]')));
        expect(m.uci[2], matches(RegExp(r'[a-h]')));
        expect(m.uci[3], matches(RegExp(r'[1-8]')));
      }
    });

    test('weighted selection covers all moves over many samples', () {
      const startFen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final seen = <String>{};
      for (int i = 0; i < 500; i++) {
        final move = OpeningBook.pickMove(startFen);
        if (move != null) seen.add(move);
      }
      // Should see at least the top 3 moves (e2e4, d2d4, g1f3)
      expect(seen.length, greaterThanOrEqualTo(3));
      expect(seen, contains('e2e4'));
      expect(seen, contains('d2d4'));
    });
  });
}
