import 'package:chess/chess.dart' as chess;
import 'evaluation.dart';
import 'transposition.dart';

/// Result of a search at a given depth.
class SearchResult {
  final String bestMove; // UCI format
  final int score; // centipawns from root side's perspective
  final int depth;
  final int nodesSearched;

  SearchResult({
    required this.bestMove,
    required this.score,
    required this.depth,
    required this.nodesSearched,
  });
}

/// Alpha-beta search with iterative deepening, transposition table,
/// move ordering, and quiescence search.
class AlphaBetaSearch {
  final chess.Chess _game;
  bool _stopped = false;
  int _nodes = 0;

  final List<List<String?>> _killers;
  final Map<String, int> _history = {};
  final TranspositionTable _tt = TranspositionTable();

  AlphaBetaSearch(this._game)
      : _killers = List.generate(64, (_) => [null, null]);

  void stop() => _stopped = true;

  SearchResult? search(
    int maxDepth, {
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

    // Check TT for best move from previous iteration to search first
    final hash = _game.fen.hashCode;
    final ttEntry = _tt.probe(hash);
    _orderMoves(moves, 0, ttBestMove: ttEntry?.bestMove);

    String? bestMove;
    int bestScore = -999999;
    int alpha = -999999;
    const beta = 999999;

    for (final move in moves) {
      if (_stopped) return null;

      final uci =
          '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';

      _game.move({
        'from': move.fromAlgebraic,
        'to': move.toAlgebraic,
        'promotion': move.promotion?.name,
      });

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
      hash: hash,
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

    if (_game.in_checkmate) return -99999 + ply;
    if (_game.in_draw || _game.in_stalemate || _game.in_threefold_repetition) {
      return 0;
    }

    // Transposition table lookup
    final hash = _game.fen.hashCode;
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

    if (depth <= 0) {
      return _quiescence(alpha, beta, ply);
    }

    final moves = _game.generate_moves();
    if (moves.isEmpty) return evaluate(_game);

    _orderMoves(moves, ply, ttBestMove: ttEntry?.bestMove);

    String? bestMove;
    int bestScore = -999999;
    final origAlpha = alpha;

    for (final move in moves) {
      if (_stopped) return 0;

      _game.move({
        'from': move.fromAlgebraic,
        'to': move.toAlgebraic,
        'promotion': move.promotion?.name,
      });

      _nodes++;
      final score = -_alphaBeta(depth - 1, -beta, -alpha, ply + 1);
      _game.undo();

      if (score > bestScore) {
        bestScore = score;
        bestMove =
            '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';
      }

      if (score >= beta) {
        // Beta cutoff
        final uci =
            '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';
        if (ply < _killers.length) {
          _killers[ply][1] = _killers[ply][0];
          _killers[ply][0] = uci;
        }
        _history[uci] = (_history[uci] ?? 0) + depth * depth;

        _tt.store(
          hash: hash,
          depth: depth,
          score: score,
          flag: TTFlag.lowerBound,
          bestMove: uci,
        );
        return beta;
      }
      if (score > alpha) alpha = score;
    }

    // Store in TT
    final flag = bestScore <= origAlpha ? TTFlag.upperBound : TTFlag.exact;
    _tt.store(
      hash: hash,
      depth: depth,
      score: bestScore,
      flag: flag,
      bestMove: bestMove,
    );

    return alpha;
  }

  int _quiescence(int alpha, int beta, int ply) {
    if (_stopped) return 0;

    final standPat = evaluate(_game);
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;

    final moves = _game.generate_moves();
    final captures = moves.where((m) {
      final target = _game.get(m.toAlgebraic);
      return target != null;
    }).toList();

    _orderCaptures(captures);

    for (final move in captures) {
      if (_stopped) return 0;

      _game.move({
        'from': move.fromAlgebraic,
        'to': move.toAlgebraic,
        'promotion': move.promotion?.name,
      });

      _nodes++;
      final score = -_quiescence(-beta, -alpha, ply + 1);
      _game.undo();

      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }

    return alpha;
  }

  void _orderMoves(List<chess.Move> moves, int ply, {String? ttBestMove}) {
    moves.sort((a, b) {
      final scoreA = _moveScore(a, ply, ttBestMove: ttBestMove);
      final scoreB = _moveScore(b, ply, ttBestMove: ttBestMove);
      return scoreB.compareTo(scoreA);
    });
  }

  int _moveScore(chess.Move move, int ply, {String? ttBestMove}) {
    final uci =
        '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';

    // TT best move gets highest priority
    if (ttBestMove != null && uci == ttBestMove) return 20000;

    final victim = _game.get(move.toAlgebraic);
    if (victim != null) {
      final attacker = _game.get(move.fromAlgebraic);
      final victimVal = pieceValues[victim.type] ?? 0;
      final attackerVal = pieceValues[attacker?.type] ?? 0;
      return 10000 + victimVal - (attackerVal ~/ 10);
    }

    if (move.promotion != null) return 9000;

    if (ply < _killers.length) {
      if (_killers[ply][0] == uci) return 8000;
      if (_killers[ply][1] == uci) return 7000;
    }

    return _history[uci] ?? 0;
  }

  void _orderCaptures(List<chess.Move> captures) {
    captures.sort((a, b) {
      final victimA = _game.get(a.toAlgebraic);
      final victimB = _game.get(b.toAlgebraic);
      final valA = pieceValues[victimA?.type] ?? 0;
      final valB = pieceValues[victimB?.type] ?? 0;
      return valB.compareTo(valA);
    });
  }
}
