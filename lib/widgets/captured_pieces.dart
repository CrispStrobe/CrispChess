import 'package:flutter/material.dart';
import '../chess/chess_game.dart';

/// Displays captured pieces for one side with material advantage.
class CapturedPieces extends StatelessWidget {
  final List<List<ChessPiece?>> board;
  final PieceColor color; // Which color's captured pieces to show

  const CapturedPieces({
    super.key,
    required this.board,
    required this.color,
  });

  // Starting material count
  static const _startingCounts = {
    PieceType.pawn: 8,
    PieceType.knight: 2,
    PieceType.bishop: 2,
    PieceType.rook: 2,
    PieceType.queen: 1,
  };

  static const _pieceValues = {
    PieceType.pawn: 1,
    PieceType.knight: 3,
    PieceType.bishop: 3,
    PieceType.rook: 5,
    PieceType.queen: 9,
  };

  static const _pieceSymbols = {
    PieceType.queen: '♛',
    PieceType.rook: '♜',
    PieceType.bishop: '♝',
    PieceType.knight: '♞',
    PieceType.pawn: '♟',
  };

  @override
  Widget build(BuildContext context) {
    // Count pieces currently on board
    final onBoard = <PieceType, int>{};
    for (final row in board) {
      for (final piece in row) {
        if (piece != null && piece.color == color) {
          onBoard[piece.type] = (onBoard[piece.type] ?? 0) + 1;
        }
      }
    }

    // Compute captured (starting - on board)
    final captured = <PieceType>[];
    for (final entry in _startingCounts.entries) {
      final missing = entry.value - (onBoard[entry.key] ?? 0);
      for (int i = 0; i < missing; i++) {
        captured.add(entry.key);
      }
    }

    // Material advantage
    int ourMaterial = 0;
    int theirMaterial = 0;
    for (final row in board) {
      for (final piece in row) {
        if (piece == null) continue;
        final val = _pieceValues[piece.type] ?? 0;
        if (piece.color == color) {
          ourMaterial += val;
        } else {
          theirMaterial += val;
        }
      }
    }
    final advantage = ourMaterial - theirMaterial;

    if (captured.isEmpty) return const SizedBox(height: 20);

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          // Captured piece symbols
          ...captured.map((type) => Text(
                _pieceSymbols[type] ?? '?',
                style: TextStyle(
                  fontSize: 14,
                  color: color == PieceColor.white
                      ? Colors.grey.shade400
                      : Colors.grey.shade700,
                ),
              )),
          // Material advantage badge
          if (advantage < 0) // Opponent has advantage = we lost more
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '+${-advantage}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
