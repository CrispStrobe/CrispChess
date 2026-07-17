// Web stub for the native bitboard search. The bitboard engine is 64-bit and
// cannot compile under dart2js, so web never imports it. This preserves the
// same API for compilation; it is never called at runtime because the web code
// path uses the chess-package search directly (DartEngine._searchWeb).
import 'package:crisp_chess_engine/crisp_chess_engine.dart';

SearchResult? searchPositionNative(
    String baseFen, List<String> moves, int depth, int budgetMs) {
  throw UnsupportedError('bitboard engine is native-only');
}

/// Whether this build uses the bitboard engine (false on web).
const bool usesBitboardEngine = false;
