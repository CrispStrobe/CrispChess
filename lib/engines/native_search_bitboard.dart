// Native fixed-position search backed by the bitboard engine (~20-60x the
// nodes/sec of the chess-package search). Selected via conditional import in
// native_search.dart; never compiled for web (bitboards are 64-bit, which
// dart2js can't represent).
import 'package:crisp_chess_engine/bitboard.dart';

/// Replay [moves] from [baseFen] and search the resulting position to [depth],
/// bounded by [budgetMs] (0 = no budget). The replay also collects the game's
/// position history so the search avoids repeating positions already reached —
/// otherwise it can draw a won game (or shuffle a won ending) by repetition.
/// Returns the best move from the last completed depth, or null if there are no
/// legal moves.
SearchResult? searchPositionNative(
    String baseFen, List<String> moves, int depth, int budgetMs) {
  final pos = Position.fromFen(baseFen);
  final history = <int>[pos.hash()];
  for (final uci in moves) {
    final m = pos.moveFromUci(uci);
    if (m < 0) break; // unparseable/illegal — stop replaying, search what we have
    pos.makeMove(m);
    history.add(pos.hash());
  }
  return BitboardSearch(pos, repetitionHistory: history).search(
    depth,
    timeBudget: budgetMs > 0 ? Duration(milliseconds: budgetMs) : null,
  );
}

/// Whether this build uses the bitboard engine (true on native).
const bool usesBitboardEngine = true;
