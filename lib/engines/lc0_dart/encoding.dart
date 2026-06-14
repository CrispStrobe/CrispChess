/// Lc0 112-plane board encoding for neural network input.
///
/// The input tensor shape is [1, 112, 8, 8]:
///   - 8 history slots x 13 planes each = 104 planes
///   - 8 auxiliary planes
///
/// Each history slot has 13 planes:
///   planes 0-5:   our pieces (P, N, B, R, Q, K)
///   planes 6-11:  their pieces (P, N, B, R, Q, K)
///   plane 12:     repetition count (1 if position repeated)
///
/// The board is ALWAYS from the current player's perspective:
///   - When white to move: a1 = index 0, h8 = index 63 (normal)
///   - When black to move: board is flipped vertically
///     (a8 maps to index 0, h1 maps to index 63, and colors swap)
///
/// Auxiliary planes (104-111):
///   104: castling — our kingside
///   105: castling — our queenside
///   106: castling — their kingside
///   107: castling — their queenside
///   108: is black to move (all 1s if black, else 0)
///   109: rule-50 count / 100
///   110: zeros (unused / move count)
///   111: all ones (bias plane)
library;

import 'dart:typed_data';
import 'package:chess/chess.dart' as chess;

/// Encode a position (FEN) into 112 planes of 8x8 = 7168 floats.
///
/// [fen] is the current position FEN string.
/// [historyFens] is an optional list of prior FENs (most recent last),
/// used to fill history slots 1-7 and detect repetitions.
Float32List encodePosition(String fen, {List<String>? historyFens}) {
  final planes = Float32List(112 * 8 * 8); // 7168

  // Build list of FENs: current + up to 7 history positions
  final fens = <String>[fen];
  if (historyFens != null) {
    // Take up to 7 most recent history positions
    final start =
        historyFens.length > 7 ? historyFens.length - 7 : 0;
    for (int i = historyFens.length - 1; i >= start; i--) {
      fens.add(historyFens[i]);
    }
  }

  final currentBoard = chess.Chess.fromFEN(fen);
  final isBlack = currentBoard.turn == chess.Color.BLACK;

  // Count board positions for repetition detection
  final positionCounts = <String, int>{};
  for (final f in fens) {
    // Use just piece placement + side to move for repetition
    final key = _boardKey(f);
    positionCounts[key] = (positionCounts[key] ?? 0) + 1;
  }

  // Encode each history slot (0 = current, 1..7 = older)
  for (int slot = 0; slot < 8; slot++) {
    if (slot < fens.length) {
      _encodeHistorySlot(planes, slot, fens[slot], isBlack, positionCounts);
    }
    // Slots beyond available history remain zeros
  }

  // Encode auxiliary planes (planes 104-111)
  _encodeAuxPlanes(planes, fen, isBlack);

  return planes;
}

/// Encode one history slot (13 planes) into the output buffer.
void _encodeHistorySlot(
  Float32List planes,
  int slot,
  String fen,
  bool isBlackToMove,
  Map<String, int> positionCounts,
) {
  final board = chess.Chess.fromFEN(fen);
  final basePlane = slot * 13;

  // Determine who is "us" and "them" based on the CURRENT position's
  // side to move (not the history position's side).
  // In lc0 encoding, "us" is always the side to move in the root position.
  final ourColor = isBlackToMove ? chess.Color.BLACK : chess.Color.WHITE;
  final theirColor = isBlackToMove ? chess.Color.WHITE : chess.Color.BLACK;

  // Piece type to plane offset within a color group
  // chess.PieceType can't be a const map key (no primitive equality)
  final pieceOrder = {
    chess.PieceType.PAWN: 0,
    chess.PieceType.KNIGHT: 1,
    chess.PieceType.BISHOP: 2,
    chess.PieceType.ROOK: 3,
    chess.PieceType.QUEEN: 4,
    chess.PieceType.KING: 5,
  };

  for (int sq = 0; sq < 64; sq++) {
    final piece = board.board[_boardIndex(sq)];
    if (piece == null) continue;

    final file = sq % 8;
    final rank = sq ~/ 8;

    // Flip board for black to move
    final outRank = isBlackToMove ? (7 - rank) : rank;
    final outIdx = outRank * 8 + file;

    final planeOffset = pieceOrder[piece.type];
    if (planeOffset == null) continue;

    if (piece.color == ourColor) {
      // Our piece: planes 0-5
      planes[(basePlane + planeOffset) * 64 + outIdx] = 1.0;
    } else if (piece.color == theirColor) {
      // Their piece: planes 6-11
      planes[(basePlane + 6 + planeOffset) * 64 + outIdx] = 1.0;
    }
  }

  // Repetition plane (plane 12 of this slot)
  final key = _boardKey(fen);
  final reps = positionCounts[key] ?? 1;
  if (reps > 1) {
    final repPlane = basePlane + 12;
    for (int i = 0; i < 64; i++) {
      planes[repPlane * 64 + i] = 1.0;
    }
  }
}

/// Encode the 8 auxiliary planes (104-111).
void _encodeAuxPlanes(Float32List planes, String fen, bool isBlack) {
  final parts = fen.split(' ');
  final castling = parts.length > 2 ? parts[2] : '-';
  final halfmoveClock = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;

  // Castling rights (from current player's perspective)
  // "Our" kingside, "our" queenside, "their" kingside, "their" queenside
  bool ourKingside, ourQueenside, theirKingside, theirQueenside;
  if (isBlack) {
    ourKingside = castling.contains('k');
    ourQueenside = castling.contains('q');
    theirKingside = castling.contains('K');
    theirQueenside = castling.contains('Q');
  } else {
    ourKingside = castling.contains('K');
    ourQueenside = castling.contains('Q');
    theirKingside = castling.contains('k');
    theirQueenside = castling.contains('q');
  }

  _fillPlane(planes, 104, ourKingside ? 1.0 : 0.0);
  _fillPlane(planes, 105, ourQueenside ? 1.0 : 0.0);
  _fillPlane(planes, 106, theirKingside ? 1.0 : 0.0);
  _fillPlane(planes, 107, theirQueenside ? 1.0 : 0.0);

  // Plane 108: is black to move
  _fillPlane(planes, 108, isBlack ? 1.0 : 0.0);

  // Plane 109: rule-50 counter (normalized)
  _fillPlane(planes, 109, halfmoveClock / 100.0);

  // Plane 110: zeros (unused)
  // Already zero

  // Plane 111: all ones (bias)
  _fillPlane(planes, 111, 1.0);
}

/// Fill an entire 8x8 plane with a constant value.
void _fillPlane(Float32List planes, int planeIndex, double value) {
  if (value == 0.0) return; // Already zero-initialized
  final start = planeIndex * 64;
  for (int i = 0; i < 64; i++) {
    planes[start + i] = value;
  }
}

/// Convert a linear square index (0=a1, 63=h8) to the chess package's
/// internal board index (0x00 = a8 in 0x88 board representation).
int _boardIndex(int sq) {
  // sq: 0 = a1 (file 0, rank 0), 63 = h8 (file 7, rank 7)
  final file = sq % 8;
  final rank = sq ~/ 8;
  // chess package uses 0x88 board: row 0 = rank 8, row 7 = rank 1
  return (7 - rank) * 16 + file;
}

/// Create a short board key from FEN for repetition detection.
/// Uses piece placement + side to move + castling + en passant.
String _boardKey(String fen) {
  final parts = fen.split(' ');
  if (parts.length >= 4) {
    return '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
  }
  return parts[0];
}
