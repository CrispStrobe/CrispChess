/// Notation style utilities.
///
/// Converts standard algebraic notation (SAN) to figurine algebraic
/// by replacing piece letters with unicode chess symbols.

/// Notation display style.
enum NotationStyle {
  algebraic,    // Nf3, Bxe5, Qd1
  figurine,     // ♞f3, ♝xe5, ♛d1
}

/// Unicode piece symbols for figurine notation.
const _figurineMap = {
  'K': '\u2654', // ♔
  'Q': '\u2655', // ♕
  'R': '\u2656', // ♖
  'B': '\u2657', // ♗
  'N': '\u2658', // ♘
};

/// Convert a SAN move string to figurine algebraic notation.
///
/// Replaces leading piece letters (K, Q, R, B, N) with unicode symbols.
/// Pawn moves (e4, dxe5) and castling (O-O, O-O-O) are left unchanged.
String toFigurine(String san) {
  if (san.isEmpty) return san;
  // Castling — leave as-is
  if (san.startsWith('O-')) return san;
  // Check if first char is a piece letter
  final first = san[0];
  if (_figurineMap.containsKey(first)) {
    return '${_figurineMap[first]}${san.substring(1)}';
  }
  return san;
}

/// Format a SAN string according to the given notation style.
String formatNotation(String san, NotationStyle style) {
  return switch (style) {
    NotationStyle.algebraic => san,
    NotationStyle.figurine => toFigurine(san),
  };
}
