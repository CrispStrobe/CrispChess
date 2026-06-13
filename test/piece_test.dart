import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/chess_game.dart';

void main() {
  group('ChessPiece', () {
    test('ChessPiece symbol uppercase for white', () {
      final piece = ChessPiece(PieceType.queen, PieceColor.white);
      expect(piece.symbol, 'Q');

      final pawn = ChessPiece(PieceType.pawn, PieceColor.white);
      expect(pawn.symbol, 'P');

      final king = ChessPiece(PieceType.king, PieceColor.white);
      expect(king.symbol, 'K');

      final knight = ChessPiece(PieceType.knight, PieceColor.white);
      expect(knight.symbol, 'N');

      final bishop = ChessPiece(PieceType.bishop, PieceColor.white);
      expect(bishop.symbol, 'B');

      final rook = ChessPiece(PieceType.rook, PieceColor.white);
      expect(rook.symbol, 'R');
    });

    test('ChessPiece symbol lowercase for black', () {
      final piece = ChessPiece(PieceType.queen, PieceColor.black);
      expect(piece.symbol, 'q');

      final pawn = ChessPiece(PieceType.pawn, PieceColor.black);
      expect(pawn.symbol, 'p');

      final king = ChessPiece(PieceType.king, PieceColor.black);
      expect(king.symbol, 'k');

      final knight = ChessPiece(PieceType.knight, PieceColor.black);
      expect(knight.symbol, 'n');

      final bishop = ChessPiece(PieceType.bishop, PieceColor.black);
      expect(bishop.symbol, 'b');

      final rook = ChessPiece(PieceType.rook, PieceColor.black);
      expect(rook.symbol, 'r');
    });

    test('all PieceType values have symbols', () {
      for (final type in PieceType.values) {
        final whitePiece = ChessPiece(type, PieceColor.white);
        final blackPiece = ChessPiece(type, PieceColor.black);

        // Symbol should not be empty
        expect(whitePiece.symbol.isNotEmpty, isTrue,
            reason: 'White $type should have a symbol');
        expect(blackPiece.symbol.isNotEmpty, isTrue,
            reason: 'Black $type should have a symbol');

        // White should be uppercase, black lowercase
        expect(whitePiece.symbol, whitePiece.symbol.toUpperCase(),
            reason: 'White $type symbol should be uppercase');
        expect(blackPiece.symbol, blackPiece.symbol.toLowerCase(),
            reason: 'Black $type symbol should be lowercase');

        // Both should represent the same letter
        expect(whitePiece.symbol.toLowerCase(), blackPiece.symbol,
            reason: 'White and black $type should use same letter');
      }
    });
  });

  group('PieceType', () {
    test('has exactly 6 values', () {
      expect(PieceType.values.length, 6);
    });

    test('contains all standard chess piece types', () {
      expect(PieceType.values, contains(PieceType.pawn));
      expect(PieceType.values, contains(PieceType.knight));
      expect(PieceType.values, contains(PieceType.bishop));
      expect(PieceType.values, contains(PieceType.rook));
      expect(PieceType.values, contains(PieceType.queen));
      expect(PieceType.values, contains(PieceType.king));
    });
  });

  group('PieceColor', () {
    test('has exactly 2 values', () {
      expect(PieceColor.values.length, 2);
    });

    test('contains white and black', () {
      expect(PieceColor.values, contains(PieceColor.white));
      expect(PieceColor.values, contains(PieceColor.black));
    });
  });
}
