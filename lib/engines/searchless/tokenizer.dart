/// Input encoding of DeepMind's searchless-chess transformers
/// (google-deepmind/searchless_chess, Apache-2.0): 77 tokens for the FEN,
/// then the move's action id, then a 0.
library;

import 'package:chess/chess.dart' as chess;

const List<String> _characters = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', //
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', //
  'p', 'n', 'r', 'k', 'q', 'P', 'B', 'N', 'R', 'Q', 'K', 'w', '.',
];
final Map<String, int> _index = {
  for (var i = 0; i < _characters.length; i++) _characters[i]: i
};

const int fenTokenCount = 77;

/// The FEN as python-chess writes it: an en-passant square only when an
/// en-passant capture is actually legal. The Dart chess library records one
/// after every double pawn push; the model was trained on python-chess FENs.
String pythonChessFen(chess.Chess board) {
  final f = board.fen.split(' ');
  if (f[3] != '-') {
    final ep = f[3];
    final legalEp = board.generate_moves().any((m) =>
        m.toAlgebraic == ep && (m.flags & chess.Chess.BITS_EP_CAPTURE) != 0);
    if (!legalEp) f[3] = '-';
  }
  return f.join(' ');
}

/// Tokens of [fen] exactly as `searchless_chess.src.tokenizer.tokenize`.
List<int> tokenizeFen(String fen) {
  final parts = fen.split(' ');
  final board = parts[1] + parts[0].replaceAll('/', '');
  final out = <int>[];
  for (final c in board.split('')) {
    final n = int.tryParse(c);
    if (n != null && n >= 1 && n <= 8) {
      out.addAll(List.filled(n, _index['.']!));
    } else {
      out.add(_index[c]!);
    }
  }
  final castling = parts[2];
  if (castling == '-') {
    out.addAll(List.filled(4, _index['.']!));
  } else {
    for (final c in castling.split('')) {
      out.add(_index[c]!);
    }
    out.addAll(List.filled(4 - castling.length, _index['.']!));
  }
  final ep = parts[3];
  if (ep == '-') {
    out.addAll(List.filled(2, _index['.']!));
  } else {
    for (final c in ep.split('')) {
      out.add(_index[c]!);
    }
  }
  for (final field in [parts[4], parts[5]]) {
    final padded = field.padRight(3, '.');
    for (final c in padded.split('')) {
      out.add(_index[c]!);
    }
  }
  assert(out.length == fenTokenCount, 'got ${out.length} tokens for $fen');
  return out;
}
