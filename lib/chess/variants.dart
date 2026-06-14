/// Chess variant win conditions.
///
/// Provides additional win condition checks for variant modes
/// that run on top of the standard chess.Chess engine.

/// Check if the side that just moved has won via King of the Hill.
/// Win by placing your king on d4, d5, e4, or e5.
bool checkKothWin(String fen) {
  final board = fen.split(' ')[0];
  final rows = board.split('/');
  // Center squares: d4 = row 4, col 3; d5 = row 3, col 3;
  // e4 = row 4, col 4; e5 = row 3, col 4
  // In FEN, row 0 = rank 8 (top), row 7 = rank 1 (bottom)
  // d5 = row 3, col 3; e5 = row 3, col 4
  // d4 = row 4, col 3; e4 = row 4, col 4

  for (final (r, c) in [(3, 3), (3, 4), (4, 3), (4, 4)]) {
    final piece = _pieceAt(rows, r, c);
    if (piece == 'K' || piece == 'k') return true;
  }
  return false;
}

/// Get which side's king is on a center square (for KOTH).
/// Returns 'White', 'Black', or null.
String? kothWinner(String fen) {
  final rows = fen.split(' ')[0].split('/');
  for (final (r, c) in [(3, 3), (3, 4), (4, 3), (4, 4)]) {
    final piece = _pieceAt(rows, r, c);
    if (piece == 'K') return 'White';
    if (piece == 'k') return 'Black';
  }
  return null;
}

/// Check if the side that just moved has won via Three-check.
/// Requires external tracking of check counts.
bool checkThreeCheckWin(int whiteChecks, int blackChecks) {
  return whiteChecks >= 3 || blackChecks >= 3;
}

/// Get the piece character at a board position from FEN rows.
String? _pieceAt(List<String> rows, int row, int col) {
  if (row < 0 || row >= rows.length) return null;
  int c = 0;
  for (final ch in rows[row].split('')) {
    final n = int.tryParse(ch);
    if (n != null) {
      c += n;
      if (c > col) return null; // empty square
    } else {
      if (c == col) return ch;
      c++;
    }
  }
  return null;
}
