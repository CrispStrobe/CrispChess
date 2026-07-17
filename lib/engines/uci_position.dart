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
  final fens = <String>[game.fen];

  if (movesIdx >= 0) {
    for (final uci in parts.sublist(movesIdx + 1)) {
      if (!_playUci(game, uci)) {
        debugPrint('[uci_position] Could not apply move "$uci"');
        break;
      }
      fens.add(game.fen);
    }
  }

  if (limit > 0 && fens.length > limit) {
    return fens.sublist(fens.length - limit);
  }
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
