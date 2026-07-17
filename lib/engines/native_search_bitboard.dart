// Native fixed-position search backed by the bitboard engine (~20-60x the
// nodes/sec of the chess-package search). Selected via conditional import in
// native_search.dart; never compiled for web (bitboards are 64-bit, which
// dart2js can't represent).
import 'package:crisp_chess_engine/bitboard.dart';

/// Search [fen] to [depth], bounded by [budgetMs] (0 = no budget). Returns the
/// best move from the last completed depth, or null if there are no legal moves.
SearchResult? searchPositionNative(String fen, int depth, int budgetMs) {
  final pos = Position.fromFen(fen);
  return BitboardSearch(pos).search(
    depth,
    timeBudget: budgetMs > 0 ? Duration(milliseconds: budgetMs) : null,
  );
}

/// Whether this build uses the bitboard engine (true on native).
const bool usesBitboardEngine = true;
