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
/// Auxiliary planes (104-111), following lc0's INPUT_CLASSICAL_112_PLANE.
/// Queenside comes first, and the rule-50 plane carries a raw ply count — the
/// division by 100 belongs to the "hectoplies" input formats, which the Maia
/// networks are not. Both were the other way round here until a diff against
/// lc0's own encoder (src/neural/encoder.cc) showed it:
///   104: castling — our queenside
///   105: castling — our kingside
///   106: castling — their queenside
///   107: castling — their kingside
///   108: is black to move (all 1s if black, else 0)
///   109: rule-50 ply count, unscaled
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

  // The game so far, oldest first, with the current position last.
  final played = <String>[...?historyFens, fen];

  final currentBoard = chess.Chess.fromFEN(fen);
  final isBlack = currentBoard.turn == chess.Color.BLACK;

  // A slot's repetition plane says whether *that* position had already
  // occurred earlier in the game, so it has to be counted over the whole game
  // and attributed per position. Counting occurrences inside the eight-slot
  // window instead marks the older slots as repetitions of positions that had
  // not happened yet when they were played.
  final seen = <String, int>{};
  final repeatedBefore = List<bool>.filled(played.length, false);
  for (int i = 0; i < played.length; i++) {
    final key = _boardKey(played[i]);
    repeatedBefore[i] = (seen[key] ?? 0) >= 1;
    seen[key] = (seen[key] ?? 0) + 1;
  }

  // Encode each history slot (0 = current, 1..7 = older). Slots beyond the
  // start of the game stay zero.
  for (int slot = 0; slot < 8; slot++) {
    final index = played.length - 1 - slot;
    if (index < 0) break;
    _encodeHistorySlot(planes, slot, played[index], isBlack,
        repeatedBefore[index]);
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
  bool wasRepetition,
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
  if (wasRepetition) {
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

  // Queenside first — see the plane list above.
  _fillPlane(planes, 104, ourQueenside ? 1.0 : 0.0);
  _fillPlane(planes, 105, ourKingside ? 1.0 : 0.0);
  _fillPlane(planes, 106, theirQueenside ? 1.0 : 0.0);
  _fillPlane(planes, 107, theirKingside ? 1.0 : 0.0);

  // Plane 108: is black to move
  _fillPlane(planes, 108, isBlack ? 1.0 : 0.0);

  // Plane 109: rule-50 counter, as a raw ply count.
  _fillPlane(planes, 109, halfmoveClock.toDouble());

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
