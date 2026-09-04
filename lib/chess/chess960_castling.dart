/// Castling for Chess960, which `package:chess` cannot do.
///
/// That library hardcodes the standard geometry — king on e1/e8 moving two
/// squares to g or c — so in a shuffled position it generates no castling move
/// at all and silently ignores the `KQkq` rights in the FEN. The app offers
/// Chess960 as a variant, so a player who set up a game with the king on b1
/// simply could never castle, with nothing to say why.
///
/// This adds it on top rather than forking the library: generate the castling
/// moves for a position, and apply one by producing the FEN that results.
/// Everything else — ordinary moves, check detection, the game tree — stays
/// with `package:chess`.
///
/// Castling in Chess960 keeps the standard *destinations*: the king ends on the
/// g-file (kingside) or c-file (queenside) and the rook on f or d, wherever the
/// two started. Either may already be standing on its destination, and the two
/// may pass through each other, so the emptiness test is "every square between
/// is free, ignoring these two pieces".
library;

import 'package:chess/chess.dart' as chess;

/// A castling move available in a position.
class Chess960Castle {
  /// Standard UCI: the king's square to its destination, e.g. `b1g1`.
  ///
  /// The app speaks this form everywhere — the board moves a king to a target
  /// square, and the engines are handed ordinary UCI. The king-takes-rook form
  /// (`b1h1`) is accepted as input but never produced.
  final String uci;

  /// True for kingside (the rook that starts right of the king).
  final bool kingside;

  const Chess960Castle(this.uci, {required this.kingside});
}

const _files = 'abcdefgh';

String _square(int file, int rank) => '${_files[file]}${rank + 1}';

/// The castling moves available to the side to move in [game].
///
/// Empty for a standard position: there `package:chess` generates castling
/// itself, and producing it twice would offer the move twice.
List<Chess960Castle> chess960Castles(chess.Chess game) {
  final fen = game.fen;
  final board = _Board.fromFen(fen);
  if (board.isStandardCastlingGeometry) return const [];

  final white = board.whiteToMove;
  final rank = white ? 0 : 7;
  final kingFile = board.fileOf(white ? 'K' : 'k', rank);
  if (kingFile == null) return const [];

  final result = <Chess960Castle>[];
  for (final kingside in [true, false]) {
    if (!board.hasRight(white: white, kingside: kingside)) continue;
    final rookFile = board.castlingRookFile(rank, kingFile, kingside: kingside);
    if (rookFile == null) continue;

    final kingTo = kingside ? 6 : 2; // g-file or c-file
    final rookTo = kingside ? 5 : 3; // f-file or d-file

    if (!board.pathIsClear(rank, kingFile, kingTo, kingFile, rookFile)) continue;
    if (!board.pathIsClear(rank, rookFile, rookTo, kingFile, rookFile)) continue;
    if (!_kingIsSafeAlongPath(board, rank, kingFile, kingTo, rookFile)) continue;

    result.add(Chess960Castle(
      '${_square(kingFile, rank)}${_square(kingTo, rank)}',
      kingside: kingside,
    ));
  }
  return result;
}

/// The FEN after playing [uci] as a Chess960 castling move, or null if it is
/// not one that is available.
///
/// Accepts both the king-to-destination form this module emits (`b1g1`) and
/// the king-takes-rook form the UCI spec uses for Chess960 (`b1h1`), because an
/// engine told `UCI_Chess960` may answer with either.
String? applyChess960Castle(chess.Chess game, String uci) {
  if (uci.length < 4) return null;
  final board = _Board.fromFen(game.fen);
  if (board.isStandardCastlingGeometry) return null;

  final white = board.whiteToMove;
  final rank = white ? 0 : 7;
  final kingFile = board.fileOf(white ? 'K' : 'k', rank);
  if (kingFile == null) return null;

  final from = uci.substring(0, 2);
  final to = uci.substring(2, 4);
  if (from != _square(kingFile, rank)) return null;

  for (final castle in chess960Castles(game)) {
    final kingside = castle.kingside;
    final rookFile = board.castlingRookFile(rank, kingFile, kingside: kingside);
    final matches = to == castle.uci.substring(2) ||
        (rookFile != null && to == _square(rookFile, rank));
    if (!matches) continue;
    return board.afterCastle(rank, kingFile, rookFile!, kingside: kingside);
  }
  return null;
}

/// Whether the king is safe on every square it crosses, itself included.
///
/// Tested by putting the king on each square in a position with the castling
/// rook lifted — the rook cannot shield the king from anything, and leaving it
/// in place would block a rank attack that castling does not actually escape.
bool _kingIsSafeAlongPath(
    _Board board, int rank, int kingFrom, int kingTo, int rookFile) {
  final step = kingTo >= kingFrom ? 1 : -1;
  for (var file = kingFrom;; file += step) {
    if (!board.kingIsSafeAt(rank, file, kingFrom, rookFile)) return false;
    if (file == kingTo) break;
  }
  return true;
}

/// The piece placement of a FEN, as an 8x8 grid indexed [rank][file] with rank
/// 0 = rank 1. Everything here is string manipulation so it stays independent
/// of the chess library's internals.
class _Board {
  final List<List<String?>> squares;
  final bool whiteToMove;
  final String castling;
  final String enPassant;
  final int halfmove;
  final int fullmove;

  _Board(this.squares, this.whiteToMove, this.castling, this.enPassant,
      this.halfmove, this.fullmove);

  factory _Board.fromFen(String fen) {
    final parts = fen.split(' ');
    final grid = List.generate(8, (_) => List<String?>.filled(8, null));
    final rows = parts[0].split('/');
    for (var i = 0; i < 8; i++) {
      var file = 0;
      for (final ch in rows[i].split('')) {
        final empty = int.tryParse(ch);
        if (empty != null) {
          file += empty;
        } else {
          grid[7 - i][file] = ch; // row 0 of the FEN is rank 8
          file++;
        }
      }
    }
    return _Board(
      grid,
      parts.length < 2 || parts[1] == 'w',
      parts.length > 2 ? parts[2] : '-',
      parts.length > 3 ? parts[3] : '-',
      parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0,
      parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1,
    );
  }

  /// True when both kings that still hold rights sit on the e-file, i.e. the
  /// standard layout `package:chess` already handles.
  bool get isStandardCastlingGeometry {
    for (final white in [true, false]) {
      if (!hasRight(white: white, kingside: true) &&
          !hasRight(white: white, kingside: false)) {
        continue;
      }
      if (fileOf(white ? 'K' : 'k', white ? 0 : 7) != 4) return false;
    }
    return true;
  }

  int? fileOf(String piece, int rank) {
    for (var file = 0; file < 8; file++) {
      if (squares[rank][file] == piece) return file;
    }
    return null;
  }

  bool hasRight({required bool white, required bool kingside}) {
    final flag = kingside ? (white ? 'K' : 'k') : (white ? 'Q' : 'q');
    return castling.contains(flag);
  }

  /// The rook that castles on the given side: the outermost rook of that colour
  /// on the back rank, beyond the king.
  int? castlingRookFile(int rank, int kingFile, {required bool kingside}) {
    final rook = rank == 0 ? 'R' : 'r';
    if (kingside) {
      for (var file = 7; file > kingFile; file--) {
        if (squares[rank][file] == rook) return file;
      }
    } else {
      for (var file = 0; file < kingFile; file++) {
        if (squares[rank][file] == rook) return file;
      }
    }
    return null;
  }

  /// Every square strictly between [from] and [to] — plus [to] itself — is
  /// empty, ignoring the castling king and rook, which may be standing in the
  /// way of each other.
  bool pathIsClear(int rank, int from, int to, int kingFile, int rookFile) {
    if (from == to) return true;
    final step = to > from ? 1 : -1;
    for (var file = from + step;; file += step) {
      final occupant = squares[rank][file];
      if (occupant != null && file != kingFile && file != rookFile) return false;
      if (file == to) break;
    }
    return true;
  }

  /// Whether the side to move's king would be in check standing on
  /// [rank]/[file], with its own square and the castling rook's square vacated.
  bool kingIsSafeAt(int rank, int file, int kingFile, int rookFile) {
    final king = whiteToMove ? 'K' : 'k';
    final grid = [for (final row in squares) [...row]];
    grid[rank][kingFile] = null;
    grid[rank][rookFile] = null;
    grid[rank][file] = king;
    // No castling rights and no en passant: this position exists only to ask
    // whether the king is attacked.
    final probe = chess.Chess.fromFEN(
      '${_serialize(grid)} ${whiteToMove ? 'w' : 'b'} - - 0 1',
      check_validity: false,
    );
    return !probe.in_check;
  }

  /// The FEN after castling: king to g/c, rook to f/d, that side's rights gone.
  String afterCastle(int rank, int kingFile, int rookFile,
      {required bool kingside}) {
    final grid = [for (final row in squares) [...row]];
    final king = whiteToMove ? 'K' : 'k';
    final rook = whiteToMove ? 'R' : 'r';
    grid[rank][kingFile] = null;
    grid[rank][rookFile] = null;
    grid[rank][kingside ? 6 : 2] = king;
    grid[rank][kingside ? 5 : 3] = rook;

    final dropped = whiteToMove ? 'KQ' : 'kq';
    var rights =
        castling.split('').where((c) => !dropped.contains(c)).join();
    if (rights.isEmpty) rights = '-';

    // Castling is reversible, so the halfmove clock keeps counting; Black
    // completing a move advances the full-move number.
    return '${_serialize(grid)} ${whiteToMove ? 'b' : 'w'} $rights - '
        '${halfmove + 1} ${whiteToMove ? fullmove : fullmove + 1}';
  }

  static String _serialize(List<List<String?>> grid) {
    final rows = <String>[];
    for (var rank = 7; rank >= 0; rank--) {
      final buffer = StringBuffer();
      var empty = 0;
      for (var file = 0; file < 8; file++) {
        final piece = grid[rank][file];
        if (piece == null) {
          empty++;
        } else {
          if (empty > 0) buffer.write(empty);
          empty = 0;
          buffer.write(piece);
        }
      }
      if (empty > 0) buffer.write(empty);
      rows.add(buffer.toString());
    }
    return rows.join('/');
  }
}
