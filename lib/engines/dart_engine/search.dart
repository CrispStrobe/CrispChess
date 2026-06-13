import 'package:chess/chess.dart' as chess;
import 'evaluation.dart';

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

/// Alpha-beta search with iterative deepening, move ordering,
/// and quiescence search.
class AlphaBetaSearch {
  final chess.Chess _game;
  bool _stopped = false;
  int _nodes = 0;

  // Killer moves for move ordering (2 per ply)
  final List<List<String?>> _killers;

  // History heuristic table
  final Map<String, int> _history = {};

  AlphaBetaSearch(this._game)
      : _killers = List.generate(64, (_) => [null, null]);

  /// Stop the search.
  void stop() => _stopped = true;

  /// Run iterative deepening search up to [maxDepth].
  /// Calls [onDepthComplete] after each completed depth.
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

    _orderMoves(moves, 0);

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
      if (score > alpha) {
        alpha = score;
      }
    }

    if (bestMove == null) return null;

    return SearchResult(
      bestMove: bestMove,
      score: bestScore,
      depth: depth,
      nodesSearched: _nodes,
    );
  }

  int _alphaBeta(int depth, int alpha, int beta, int ply) {
    if (_stopped) return 0;

    // Check for terminal states
    if (_game.in_checkmate) return -99999 + ply; // prefer faster mates
    if (_game.in_draw ||
        _game.in_stalemate ||
        _game.in_threefold_repetition) {
      return 0;
    }

    if (depth <= 0) {
      return _quiescence(alpha, beta, ply);
    }

    final moves = _game.generate_moves();
    if (moves.isEmpty) return evaluate(_game);

    _orderMoves(moves, ply);

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

      if (score >= beta) {
        // Beta cutoff — store killer move
        final uci =
            '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';
        if (ply < _killers.length) {
          _killers[ply][1] = _killers[ply][0];
          _killers[ply][0] = uci;
        }
        _history[uci] = (_history[uci] ?? 0) + depth * depth;
        return beta;
      }
      if (score > alpha) {
        alpha = score;
      }
    }

    return alpha;
  }

  /// Quiescence search: only consider captures at leaf nodes
  /// to avoid the horizon effect.
  int _quiescence(int alpha, int beta, int ply) {
    if (_stopped) return 0;

    final standPat = evaluate(_game);
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;

    // Generate captures only
    final moves = _game.generate_moves();
    final captures = moves.where((m) {
      final target = _game.get(m.toAlgebraic);
      return target != null;
    }).toList();

    // Order captures by MVV-LVA
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

  /// Order moves for better alpha-beta pruning.
  /// Priority: captures (MVV-LVA) > killers > history heuristic.
  void _orderMoves(List<chess.Move> moves, int ply) {
    moves.sort((a, b) {
      final scoreA = _moveScore(a, ply);
      final scoreB = _moveScore(b, ply);
      return scoreB.compareTo(scoreA); // descending
    });
  }

  int _moveScore(chess.Move move, int ply) {
    final uci =
        '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';

    // Captures scored by MVV-LVA
    final victim = _game.get(move.toAlgebraic);
    if (victim != null) {
      final attacker = _game.get(move.fromAlgebraic);
      final victimVal = pieceValues[victim.type] ?? 0;
      final attackerVal = pieceValues[attacker?.type] ?? 0;
      return 10000 + victimVal - (attackerVal ~/ 10);
    }

    // Promotions
    if (move.promotion != null) return 9000;

    // Killer moves
    if (ply < _killers.length) {
      if (_killers[ply][0] == uci) return 8000;
      if (_killers[ply][1] == uci) return 7000;
    }

    // History heuristic
    return _history[uci] ?? 0;
  }

  /// Order captures by Most Valuable Victim - Least Valuable Attacker.
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
