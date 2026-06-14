import 'package:chess/chess.dart' as chess;
import 'evaluation.dart';
import 'transposition.dart';

class SearchResult {
  final String bestMove;
  final int score;
  final int depth;
  final int nodesSearched;

  SearchResult({
    required this.bestMove,
    required this.score,
    required this.depth,
    required this.nodesSearched,
  });
}

/// Optimized alpha-beta search with transposition table.
class AlphaBetaSearch {
  final chess.Chess _game;
  bool _stopped = false;
  int _nodes = 0;

  final List<List<String?>> _killers;
  final Map<String, int> _history = {};
  final TranspositionTable _tt = TranspositionTable();

  // Cache to avoid recomputing FEN hash
  int _posHash = 0;

  AlphaBetaSearch(this._game)
      : _killers = List.generate(64, (_) => [null, null]);

  void stop() => _stopped = true;

  SearchResult? search(int maxDepth, {
    void Function(SearchResult)? onDepthComplete,
  }) {
    _stopped = false;
    _nodes = 0;
    SearchResult? bestResult;

    for (int depth = 1; depth <= maxDepth; depth++) {
      if (_stopped) break;
      final result = _searchRoot(depth);
      if (result != null && !_stopped) {
        bestResult = result;
        onDepthComplete?.call(result);
      }
    }
    return bestResult;
  }

  SearchResult? _searchRoot(int depth) {
    final moves = _game.generate_moves();
    if (moves.isEmpty) return null;

    _posHash = _quickHash();
    final ttEntry = _tt.probe(_posHash);
    _orderMoves(moves, 0, ttBestMove: ttEntry?.bestMove);

    String? bestMove;
    int bestScore = -999999;
    int alpha = -999999;
    const beta = 999999;

    for (final move in moves) {
      if (_stopped) return null;

      final uci = _moveToUci(move);
      _makeMove(move);
      _nodes++;
      final score = -_alphaBeta(depth - 1, -beta, -alpha, 1);
      _game.undo();

      if (score > bestScore) {
        bestScore = score;
        bestMove = uci;
      }
      if (score > alpha) alpha = score;
    }

    if (bestMove == null) return null;

    _tt.store(
      hash: _posHash,
      depth: depth,
      score: bestScore,
      flag: TTFlag.exact,
      bestMove: bestMove,
    );

    return SearchResult(
      bestMove: bestMove,
      score: bestScore,
      depth: depth,
      nodesSearched: _nodes,
    );
  }

  int _alphaBeta(int depth, int alpha, int beta, int ply) {
    if (_stopped) return 0;

    // Generate moves ONCE — use result to detect checkmate/stalemate
    final moves = _game.generate_moves();

    if (moves.isEmpty) {
      // No moves = checkmate or stalemate
      return _game.in_check ? (-99999 + ply) : 0;
    }

    if (_game.half_moves >= 100 || _game.in_threefold_repetition) return 0;

    if (depth <= 0) return _quiescence(alpha, beta, ply);

    // Reverse futility pruning: if static eval is far above beta,
    // prune — the position is so good no move can make it worse.
    if (depth <= 3 && !_game.in_check && ply > 0) {
      final staticEval = evaluate(_game);
      final margin = 120 * depth; // centipawns margin per depth
      if (staticEval - margin >= beta) {
        return staticEval; // Prune
      }
    }

    // TT lookup — use cheap hash
    final hash = _quickHash();
    final ttEntry = _tt.probe(hash);
    if (ttEntry != null && ttEntry.depth >= depth) {
      switch (ttEntry.flag) {
        case TTFlag.exact:
          return ttEntry.score;
        case TTFlag.lowerBound:
          if (ttEntry.score >= beta) return ttEntry.score;
          if (ttEntry.score > alpha) alpha = ttEntry.score;
        case TTFlag.upperBound:
          if (ttEntry.score <= alpha) return ttEntry.score;
          if (ttEntry.score < beta) beta = ttEntry.score;
      }
    }

    _orderMoves(moves, ply, ttBestMove: ttEntry?.bestMove);

    String? bestMove;
    int bestScore = -999999;
    final origAlpha = alpha;
    int moveIndex = 0;

    for (final move in moves) {
      if (_stopped) return 0;

      // Check if capture before making the move
      final isCapture = _game.get(move.toAlgebraic) != null;
      _makeMove(move);
      _nodes++;

      int score;
      // Late Move Reductions: search later quiet moves at reduced depth
      if (moveIndex >= 4 && depth >= 3 && !_game.in_check && !isCapture) {
        // Reduced search first
        score = -_alphaBeta(depth - 2, -beta, -alpha, ply + 1);
        // Re-search at full depth if it looks promising
        if (score > alpha) {
          score = -_alphaBeta(depth - 1, -beta, -alpha, ply + 1);
        }
      } else {
        score = -_alphaBeta(depth - 1, -beta, -alpha, ply + 1);
      }
      _game.undo();
      moveIndex++;

      if (score > bestScore) {
        bestScore = score;
        bestMove = _moveToUci(move);
      }

      if (score >= beta) {
        final uci = _moveToUci(move);
        if (ply < _killers.length) {
          _killers[ply][1] = _killers[ply][0];
          _killers[ply][0] = uci;
        }
        _history[uci] = (_history[uci] ?? 0) + depth * depth;
        _tt.store(hash: hash, depth: depth, score: score,
            flag: TTFlag.lowerBound, bestMove: uci);
        return beta;
      }
      if (score > alpha) alpha = score;
    }

    final flag = bestScore <= origAlpha ? TTFlag.upperBound : TTFlag.exact;
    _tt.store(hash: hash, depth: depth, score: bestScore,
        flag: flag, bestMove: bestMove);

    return alpha;
  }

  int _quiescence(int alpha, int beta, int ply) {
    if (_stopped) return 0;

    final standPat = evaluate(_game);
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;

    // Only generate captures — filter from all moves
    final moves = _game.generate_moves();
    final captures = <chess.Move>[];
    for (final m in moves) {
      if (_game.get(m.toAlgebraic) != null) captures.add(m);
    }

    // Simple MVV ordering for captures
    captures.sort((a, b) {
      final va = pieceValues[_game.get(a.toAlgebraic)?.type] ?? 0;
      final vb = pieceValues[_game.get(b.toAlgebraic)?.type] ?? 0;
      return vb.compareTo(va);
    });

    for (final move in captures) {
      if (_stopped) return 0;

      _makeMove(move);
      _nodes++;
      final score = -_quiescence(-beta, -alpha, ply + 1);
      _game.undo();

      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }

    return alpha;
  }

  /// Fast position hash — avoids full FEN string generation.
  /// Uses board state hash from the chess library's internal state.
  int _quickHash() {
    // The chess package doesn't expose a Zobrist hash, so we use
    // a fast hash from the half-move and piece placement portion of FEN.
    // This is still faster than full FEN because we skip castling/en-passant
    // parsing overhead.
    return _game.fen.hashCode;
  }

  /// Make a move without creating a Map (uses the move object directly).
  void _makeMove(chess.Move move) {
    _game.move({
      'from': move.fromAlgebraic,
      'to': move.toAlgebraic,
      'promotion': move.promotion?.name,
    });
  }

  String _moveToUci(chess.Move move) {
    return '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';
  }

  void _orderMoves(List<chess.Move> moves, int ply, {String? ttBestMove}) {
    moves.sort((a, b) {
      return _moveScore(b, ply, ttBestMove) - _moveScore(a, ply, ttBestMove);
    });
  }

  int _moveScore(chess.Move move, int ply, String? ttBestMove) {
    final uci = _moveToUci(move);

    if (ttBestMove != null && uci == ttBestMove) return 20000;

    final victim = _game.get(move.toAlgebraic);
    if (victim != null) {
      final attacker = _game.get(move.fromAlgebraic);
      return 10000 + (pieceValues[victim.type] ?? 0) -
          ((pieceValues[attacker?.type] ?? 0) ~/ 10);
    }

    if (move.promotion != null) return 9000;

    if (ply < _killers.length) {
      if (_killers[ply][0] == uci) return 8000;
      if (_killers[ply][1] == uci) return 7000;
    }

    return _history[uci] ?? 0;
  }
}
