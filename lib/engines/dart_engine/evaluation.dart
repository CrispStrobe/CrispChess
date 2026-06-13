import 'package:chess/chess.dart' as chess;

/// Material values in centipawns.
final pieceValues = {
  chess.PieceType.PAWN: 100,
  chess.PieceType.KNIGHT: 320,
  chess.PieceType.BISHOP: 330,
  chess.PieceType.ROOK: 500,
  chess.PieceType.QUEEN: 900,
  chess.PieceType.KING: 20000,
};

/// Piece-square tables for positional evaluation (from white's perspective).
/// Values in centipawns. Black's tables are mirrored vertically.

const _pawnTable = [
   0,  0,  0,  0,  0,  0,  0,  0,
  50, 50, 50, 50, 50, 50, 50, 50,
  10, 10, 20, 30, 30, 20, 10, 10,
   5,  5, 10, 25, 25, 10,  5,  5,
   0,  0,  0, 20, 20,  0,  0,  0,
   5, -5,-10,  0,  0,-10, -5,  5,
   5, 10, 10,-20,-20, 10, 10,  5,
   0,  0,  0,  0,  0,  0,  0,  0,
];

const _knightTable = [
  -50,-40,-30,-30,-30,-30,-40,-50,
  -40,-20,  0,  0,  0,  0,-20,-40,
  -30,  0, 10, 15, 15, 10,  0,-30,
  -30,  5, 15, 20, 20, 15,  5,-30,
  -30,  0, 15, 20, 20, 15,  0,-30,
  -30,  5, 10, 15, 15, 10,  5,-30,
  -40,-20,  0,  5,  5,  0,-20,-40,
  -50,-40,-30,-30,-30,-30,-40,-50,
];

const _bishopTable = [
  -20,-10,-10,-10,-10,-10,-10,-20,
  -10,  0,  0,  0,  0,  0,  0,-10,
  -10,  0, 10, 10, 10, 10,  0,-10,
  -10,  5,  5, 10, 10,  5,  5,-10,
  -10,  0, 10, 10, 10, 10,  0,-10,
  -10, 10, 10, 10, 10, 10, 10,-10,
  -10,  5,  0,  0,  0,  0,  5,-10,
  -20,-10,-10,-10,-10,-10,-10,-20,
];

const _rookTable = [
   0,  0,  0,  0,  0,  0,  0,  0,
   5, 10, 10, 10, 10, 10, 10,  5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
   0,  0,  0,  5,  5,  0,  0,  0,
];

const _queenTable = [
  -20,-10,-10, -5, -5,-10,-10,-20,
  -10,  0,  0,  0,  0,  0,  0,-10,
  -10,  0,  5,  5,  5,  5,  0,-10,
   -5,  0,  5,  5,  5,  5,  0, -5,
    0,  0,  5,  5,  5,  5,  0, -5,
  -10,  5,  5,  5,  5,  5,  0,-10,
  -10,  0,  5,  0,  0,  0,  0,-10,
  -20,-10,-10, -5, -5,-10,-10,-20,
];

const _kingMiddlegameTable = [
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -20,-30,-30,-40,-40,-30,-30,-20,
  -10,-20,-20,-20,-20,-20,-20,-10,
   20, 20,  0,  0,  0,  0, 20, 20,
   20, 30, 10,  0,  0, 10, 30, 20,
];

const _kingEndgameTable = [
  -50,-40,-30,-20,-20,-30,-40,-50,
  -30,-20,-10,  0,  0,-10,-20,-30,
  -30,-10, 20, 30, 30, 20,-10,-30,
  -30,-10, 30, 40, 40, 30,-10,-30,
  -30,-10, 30, 40, 40, 30,-10,-30,
  -30,-10, 20, 30, 30, 20,-10,-30,
  -30,-30,  0,  0,  0,  0,-30,-30,
  -50,-30,-30,-30,-30,-30,-30,-50,
];

final _pstTables = {
  chess.PieceType.PAWN: _pawnTable,
  chess.PieceType.KNIGHT: _knightTable,
  chess.PieceType.BISHOP: _bishopTable,
  chess.PieceType.ROOK: _rookTable,
  chess.PieceType.QUEEN: _queenTable,
};

/// Evaluate the position from the side to move's perspective.
/// Returns score in centipawns. Positive = good for side to move.
int evaluate(chess.Chess game) {
  if (game.in_checkmate) return -99999;
  if (game.in_draw || game.in_stalemate || game.in_threefold_repetition) {
    return 0;
  }

  int whiteScore = 0;
  int blackScore = 0;
  int totalMaterial = 0;

  // Count material for endgame detection
  for (final sq in chess.Chess.SQUARES.keys) {
    final piece = game.get(sq);
    if (piece == null) continue;
    if (piece.type != chess.PieceType.KING &&
        piece.type != chess.PieceType.PAWN) {
      totalMaterial += pieceValues[piece.type] ?? 0;
    }
  }

  final isEndgame = totalMaterial < 1300; // roughly queen + rook

  for (final entry in chess.Chess.SQUARES.entries) {
    final sq = entry.key;
    final int sqIndex = entry.value as int;
    final piece = game.get(sq);
    if (piece == null) continue;

    final int materialValue = pieceValues[piece.type] ?? 0;

    // Piece-square table index
    // Chess.SQUARES maps 'a8'->0, 'b8'->1, ..., 'h1'->63
    // For white: use index directly (a8=0 is rank 8)
    // For black: mirror vertically (63 - index doesn't work for files)
    final rank = sqIndex >> 4; // 0-7 (0=rank 8, 7=rank 1)
    final file = sqIndex & 0x0f; // 0-7 (0=a, 7=h)
    final whiteTableIndex = rank * 8 + file;
    final blackTableIndex = (7 - rank) * 8 + file;

    int pstValue;
    if (piece.type == chess.PieceType.KING) {
      final table = isEndgame ? _kingEndgameTable : _kingMiddlegameTable;
      pstValue = (piece.color == chess.Color.WHITE
          ? table[whiteTableIndex]
          : table[blackTableIndex]) as int;
    } else {
      final table = _pstTables[piece.type];
      if (table != null) {
        pstValue = (piece.color == chess.Color.WHITE
            ? table[whiteTableIndex]
            : table[blackTableIndex]) as int;
      } else {
        pstValue = 0;
      }
    }

    if (piece.color == chess.Color.WHITE) {
      whiteScore += materialValue + pstValue;
    } else {
      blackScore += materialValue + pstValue;
    }
  }

  // Mobility bonus: number of legal moves
  final mobility = game.generate_moves().length;

  final score = whiteScore - blackScore + (mobility * 2);

  // Return from side-to-move's perspective
  return game.turn == chess.Color.WHITE ? score : -score;
}
