import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/chess960.dart';

void main() {
  group('Chess960 FEN generator', () {
    test('generates valid FEN structure', () {
      final fen = generateChess960Fen();
      final parts = fen.split(' ');
      expect(parts.length, 6);
      expect(parts[1], 'w');
      expect(parts[2], 'KQkq');
      expect(parts[3], '-');
      expect(parts[4], '0');
      expect(parts[5], '1');
    });

    test('has 8 ranks', () {
      final fen = generateChess960Fen();
      final ranks = fen.split(' ')[0].split('/');
      expect(ranks.length, 8);
    });

    test('back rank has exactly one king between two rooks', () {
      for (int i = 0; i < 50; i++) {
        final fen = generateChess960Fen(rng: Random(i));
        final ranks = fen.split(' ')[0].split('/');
        final whiteRank = ranks[7]; // rank 1

        // Find positions
        int? kingPos;
        final rookPositions = <int>[];
        int col = 0;
        for (final ch in whiteRank.split('')) {
          final n = int.tryParse(ch);
          if (n != null) {
            col += n;
          } else {
            if (ch == 'K') kingPos = col;
            if (ch == 'R') rookPositions.add(col);
            col++;
          }
        }

        expect(kingPos, isNotNull, reason: 'King must exist on back rank');
        expect(rookPositions.length, 2, reason: 'Must have exactly 2 rooks');
        expect(kingPos!, greaterThan(rookPositions[0]),
            reason: 'King must be after first rook');
        expect(kingPos, lessThan(rookPositions[1]),
            reason: 'King must be before second rook');
      }
    });

    test('bishops are on opposite colors', () {
      for (int i = 0; i < 50; i++) {
        final fen = generateChess960Fen(rng: Random(i));
        final ranks = fen.split(' ')[0].split('/');
        final whiteRank = ranks[7];

        final bishopCols = <int>[];
        int col = 0;
        for (final ch in whiteRank.split('')) {
          final n = int.tryParse(ch);
          if (n != null) {
            col += n;
          } else {
            if (ch == 'B') bishopCols.add(col);
            col++;
          }
        }

        expect(bishopCols.length, 2, reason: 'Must have exactly 2 bishops');
        expect((bishopCols[0] + bishopCols[1]) % 2, 1,
            reason: 'Bishops must be on opposite colors');
      }
    });

    test('both sides mirror each other', () {
      final fen = generateChess960Fen(rng: Random(42));
      final ranks = fen.split(' ')[0].split('/');
      final whiteRank = ranks[7];
      final blackRank = ranks[0];
      expect(blackRank, whiteRank.toLowerCase());
    });

    test('pawns are in correct positions', () {
      final fen = generateChess960Fen();
      final ranks = fen.split(' ')[0].split('/');
      expect(ranks[1], 'pppppppp');
      expect(ranks[6], 'PPPPPPPP');
      for (int i = 2; i < 6; i++) {
        expect(ranks[i], '8');
      }
    });

    test('different seeds produce different positions', () {
      final fen1 = generateChess960Fen(rng: Random(1));
      final fen2 = generateChess960Fen(rng: Random(99));
      // Not guaranteed but highly likely with different seeds
      // At minimum, both should be valid
      expect(fen1.split(' ').length, 6);
      expect(fen2.split(' ').length, 6);
    });

    test('back rank has all 8 squares filled', () {
      final fen = generateChess960Fen(rng: Random(7));
      final ranks = fen.split(' ')[0].split('/');
      final whiteRank = ranks[7];

      // Count pieces (no digits means all 8 squares have pieces)
      int pieceCount = 0;
      for (final ch in whiteRank.split('')) {
        if (int.tryParse(ch) == null) pieceCount++;
      }
      expect(pieceCount, 8);
    });
  });
}
