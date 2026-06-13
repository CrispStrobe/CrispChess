/// Maia3 board encoding — tokenizes chess positions for the neural network.
///
/// Input tensor shape: [64, 96] float32 (6144 elements).
/// 64 squares × (12 piece channels × 8 history slots).
///
/// Ported from maia3-js/dist/encoding.js (MIT).
library;

import 'dart:typed_data';

const int seqLen = 64;
const int pieceDims = 12;
const int historySlots = 8;
const int featureDim = pieceDims * historySlots; // 96
const int tokensPerBoard = seqLen * pieceDims; // 768
const int tokensPerPosition = seqLen * featureDim; // 6144

/// Piece channel indices (white: 0–5, black: 6–11).
const Map<String, int> _pieceChannel = {
  'P': 0, 'N': 1, 'B': 2, 'R': 3, 'Q': 4, 'K': 5, // white
  'p': 6, 'n': 7, 'b': 8, 'r': 9, 'q': 10, 'k': 11, // black
};

/// Parsed board representation for encoding.
class BoardState {
  /// Piece at each square (0=a1, 63=h8), null if empty.
  final List<String?> pieces;

  /// Whose turn it is.
  final bool whiteToMove;

  /// Full FEN string.
  final String fen;

  BoardState({
    required this.pieces,
    required this.whiteToMove,
    required this.fen,
  });

  /// Parse a FEN string into a BoardState.
  factory BoardState.fromFen(String fen) {
    final parts = fen.split(' ');
    final placement = parts[0];
    final turn = parts.length > 1 ? parts[1] : 'w';

    final pieces = List<String?>.filled(64, null);
    final ranks = placement.split('/');

    // FEN rank order: rank 8 (index 0) down to rank 1 (index 7)
    for (int rankIdx = 0; rankIdx < ranks.length && rankIdx < 8; rankIdx++) {
      final rank = 7 - rankIdx; // rank 7 = a8..h8, rank 0 = a1..h1
      int file = 0;
      for (final ch in ranks[rankIdx].split('')) {
        final digit = int.tryParse(ch);
        if (digit != null) {
          file += digit;
        } else {
          if (file < 8) {
            pieces[rank * 8 + file] = ch;
          }
          file++;
        }
      }
    }

    return BoardState(
      pieces: pieces,
      whiteToMove: turn == 'w',
      fen: fen,
    );
  }

  /// Create a mirrored copy (flip ranks, swap colors).
  /// Used when it's black's turn — we always encode from white's POV.
  BoardState mirrored() {
    final newPieces = List<String?>.filled(64, null);
    for (int sq = 0; sq < 64; sq++) {
      final piece = pieces[sq];
      if (piece == null) continue;
      // Mirror: rank = 7 - rank, file stays same
      final rank = sq ~/ 8;
      final file = sq % 8;
      final mirrorRank = 7 - rank;
      final mirrorSq = mirrorRank * 8 + file;
      // Swap color
      newPieces[mirrorSq] = _swapColor(piece);
    }

    // Mirror the FEN for reference
    final parts = fen.split(' ');
    final mirroredFen = _mirrorFenPlacement(parts[0]);
    final newTurn = whiteToMove ? 'b' : 'w';

    return BoardState(
      pieces: newPieces,
      whiteToMove: !whiteToMove,
      fen: '$mirroredFen $newTurn ${parts.length > 2 ? parts.sublist(2).join(" ") : "- - 0 1"}',
    );
  }

  static String _swapColor(String piece) {
    return piece == piece.toUpperCase()
        ? piece.toLowerCase()
        : piece.toUpperCase();
  }

  static String _mirrorFenPlacement(String placement) {
    final ranks = placement.split('/');
    final mirrored = ranks.reversed.map((rank) {
      return rank.split('').map((ch) {
        final digit = int.tryParse(ch);
        if (digit != null) return ch;
        return _swapColor(ch);
      }).join();
    }).toList();
    return mirrored.join('/');
  }
}

/// Tokenize a single board position into a 768-element float array.
/// If it's black's turn, mirrors the board first.
Float32List tokenizeBoard(BoardState board) {
  final b = board.whiteToMove ? board : board.mirrored();
  final tokens = Float32List(tokensPerBoard); // 64 * 12

  for (int sq = 0; sq < 64; sq++) {
    final piece = b.pieces[sq];
    if (piece == null) continue;
    final channel = _pieceChannel[piece];
    if (channel == null) continue;
    tokens[sq * pieceDims + channel] = 1.0;
  }

  return tokens;
}

/// Build the full history tensor from a list of board states (oldest → newest).
/// Returns a [64, 96] float32 tensor (6144 elements).
///
/// Takes up to 8 history slots. If fewer than 8 boards are provided,
/// left-pads with the earliest available board.
Float32List buildHistoryTokens(List<BoardState> boards) {
  // Clamp to last 8
  final recent = boards.length > historySlots
      ? boards.sublist(boards.length - historySlots)
      : boards;

  // Left-pad with earliest if fewer than 8
  final padded = <BoardState>[];
  final earliest = recent.isNotEmpty ? recent.first : null;
  for (int i = 0; i < historySlots; i++) {
    final idx = i - (historySlots - recent.length);
    if (idx < 0) {
      padded.add(earliest ?? BoardState.fromFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'));
    } else {
      padded.add(recent[idx]);
    }
  }

  // Interleave into output: out[square*96 + slot*12 + channel]
  final output = Float32List(tokensPerPosition); // 6144
  for (int slot = 0; slot < historySlots; slot++) {
    final boardTokens = tokenizeBoard(padded[slot]);
    for (int sq = 0; sq < seqLen; sq++) {
      for (int ch = 0; ch < pieceDims; ch++) {
        output[sq * featureDim + slot * pieceDims + ch] =
            boardTokens[sq * pieceDims + ch];
      }
    }
  }

  return output;
}
