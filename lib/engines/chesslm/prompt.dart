/// How a game is written for each language model — the same rendering the
/// format scoring in tool/kaggle/chess-lm-onnx used to pick each model's
/// format, so the app shows every model the text it reads best.
library;

enum ChessLmFormat {
  /// `1.e4 e5 2.Nf3` — the Chess LLM Arena's move text.
  arena,

  /// `1. e4 e5 2. Nf3` — PGN spacing.
  spaced,

  /// `e4 e5 Nf3` — moves only.
  plain,

  /// `e2e4 e7e5 g1f3` — UCI, one token per move (chessformer).
  uci,
}

/// The game so far, written so that the next move's text follows directly.
/// Check and mate marks are dropped, as in the arena.
String renderGame(ChessLmFormat format, List<String> moves, {int firstPly = 0}) {
  final parts = <String>[];
  for (var i = 0; i < moves.length; i++) {
    final ply = firstPly + i;
    final m = format == ChessLmFormat.uci ? moves[i] : _clean(moves[i]);
    if (ply.isEven && (format == ChessLmFormat.arena || format == ChessLmFormat.spaced)) {
      final n = ply ~/ 2 + 1;
      parts.add(format == ChessLmFormat.arena ? '$n.$m' : '$n. $m');
    } else {
      parts.add(m);
    }
  }
  final next = firstPly + moves.length;
  if (next.isEven && (format == ChessLmFormat.arena || format == ChessLmFormat.spaced)) {
    parts.add('${next ~/ 2 + 1}.');
  }
  return parts.join(' ');
}

/// Text of [move] appended to [prompt] as rendered by [renderGame].
String moveText(ChessLmFormat format, String prompt, String move) {
  final m = format == ChessLmFormat.uci ? move : _clean(move);
  if (prompt.isEmpty) return m;
  if (format == ChessLmFormat.arena && prompt.endsWith('.')) return m;
  return ' $m';
}

String _clean(String san) => san.replaceAll(RegExp(r'[+#]'), '');
