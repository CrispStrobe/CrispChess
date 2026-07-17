/// Maia3 history resolution — converts move/FEN history to board states.
///
/// Ported from maia3-js/dist/history.js (MIT).
library;

import 'encoding.dart';

const String startposFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Input for history resolution.
class HistoryInput {
  final String fen;
  final List<String>? priorFens;

  HistoryInput({required this.fen, this.priorFens});
}

/// Resolve history input into a list of BoardState instances (oldest → newest).
///
/// - If priorFens is provided: parse each, append current. Clamp to last 8.
/// - Otherwise: return just [current] (buildHistoryTokens will left-pad).
List<BoardState> resolveHistory(HistoryInput input) {
  final current = BoardState.fromFen(input.fen);

  if (input.priorFens != null && input.priorFens!.isNotEmpty) {
    final boards = input.priorFens!.map(BoardState.fromFen).toList();
    boards.add(current);
    if (boards.length > historySlots) {
      return boards.sublist(boards.length - historySlots);
    }
    return boards;
  }

  return [current];
}
