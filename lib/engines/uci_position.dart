// Helpers for turning a UCI `position` command into a FEN string.
//
// Engines that only accept a FEN (e.g. Maia3) need the *current* position,
// but the app emits commands of the form
//   `position startpos moves e2e4 e7e5 ...`
// or
//   `position fen <FEN> moves ...`.
// Naively reading the FEN field (or defaulting to the start position) ignores
// the move list entirely, so the engine always sees the opening position.
// These helpers replay the moves to produce the real FEN.

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

const String _startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Valid UCI promotion suffixes. `package:chess` expects the promotion in a
/// move map as this same single lowercase letter (`PieceType.name`).
const Set<String> _promotionChars = {'q', 'r', 'b', 'n'};

/// Builds the FEN for the position described by a UCI `position` command,
/// replaying any `moves` it carries. Returns the start position FEN if the
/// command can't be parsed.
String fenFromPositionCommand(String command) =>
    fenHistoryFromPositionCommand(command, limit: 1).last;

/// Splits a UCI `position` command into its base FEN and the list of UCI moves
/// played from it. Lets an engine replay the game to recover the full position
/// history (e.g. for repetition detection) rather than only the final FEN.
({String baseFen, List<String> moves}) parsePositionCommand(String command) {
  final parts = command.trim().split(RegExp(r'\s+'));
  final movesIdx = parts.indexOf('moves');
  String baseFen = _startFen;
  if (parts.length >= 2 && parts[1] == 'fen') {
    final end = movesIdx > 0 ? movesIdx : parts.length;
    if (end > 2) baseFen = parts.sublist(2, end).join(' ');
  }
  final moves = movesIdx >= 0 ? parts.sublist(movesIdx + 1) : const <String>[];
  return (baseFen: baseFen, moves: moves);
}

/// Builds the sequence of FENs the position command passes through, oldest to
/// newest, with the *current* position last. Keeps at most [limit] entries
/// (the most recent ones).
///
/// History-conditioned engines (Maia3) need the real, consecutive positions of
/// the game. Accumulating them engine-side across `bestMove` calls does not
/// work: those only happen on the engine's own turns, so it sees every *other*
/// ply and hands the model a game that never occurred. The position command
/// already carries the full move list, so replay it and snapshot each ply.
List<String> fenHistoryFromPositionCommand(String command, {int limit = 8}) {
  final parts = command.trim().split(RegExp(r'\s+'));
  final movesIdx = parts.indexOf('moves');

  String baseFen = _startFen;
  if (parts.length >= 2 && parts[1] == 'fen') {
    final end = movesIdx > 0 ? movesIdx : parts.length;
    if (end > 2) baseFen = parts.sublist(2, end).join(' ');
  }

  final game = chess.Chess.fromFEN(baseFen);
  final moves = movesIdx >= 0 ? parts.sublist(movesIdx + 1) : const <String>[];

  // Only the last [limit] positions are kept, and generating a FEN means
  // scanning the board and building a string. Skip the plies that would be
  // thrown away — with limit 1 (the common case: an engine that just wants the
  // current position) that turns a FEN per move played into exactly one.
  final firstKept = limit > 0 ? moves.length + 1 - limit : 0;

  final fens = <String>[];
  if (firstKept <= 0) fens.add(game.fen);

  for (var i = 0; i < moves.length; i++) {
    if (!_playUci(game, moves[i])) {
      debugPrint('[uci_position] Could not apply move "${moves[i]}"');
      break;
    }
    if (i + 1 >= firstKept) fens.add(game.fen);
  }

  // A move failed to apply before anything was kept — fall back to whatever
  // position we reached, so callers always get the current one.
  if (fens.isEmpty) fens.add(game.fen);
  return fens;
}

bool _playUci(chess.Chess game, String uci) {
  if (uci.length < 4) return false;
  final move = <String, String>{
    'from': uci.substring(0, 2),
    'to': uci.substring(2, 4),
  };
  if (uci.length > 4) {
    final promo = uci.substring(4, 5).toLowerCase();
    if (_promotionChars.contains(promo)) move['promotion'] = promo;
  }
  return game.move(move);
}
