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

    final hash = _quickHash();
    final ttEntry = _tt.probe(hash);

    // Pre-compute UCI strings for all moves and build scored list
    final scored = <_ScoredMove>[];
    for (final move in moves) {
      final uci = _moveToUci(move);
      scored.add(_ScoredMove(move, uci, _moveScore(move, uci, 0, ttEntry?.bestMove)));
    }
    scored.sort((a, b) => b.score - a.score);

    String? bestMove;
    int bestScore = -999999;
    int alpha = -999999;
    const beta = 999999;

    for (final sm in scored) {
      if (_stopped) return null;

      _makeMove(sm.move);
      _nodes++;
      final score = -_alphaBeta(depth - 1, -beta, -alpha, 1);
      _game.undo();

      if (score > bestScore) {
        bestScore = score;
        bestMove = sm.uci;
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

    // TT lookup
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

    // Pre-compute UCI strings and scores for move ordering
    final scored = <_ScoredMove>[];
    for (final move in moves) {
      final uci = _moveToUci(move);
      scored.add(_ScoredMove(move, uci, _moveScore(move, uci, ply, ttEntry?.bestMove)));
    }
    scored.sort((a, b) => b.score - a.score);

    String? bestMove;
    int bestScore = -999999;
    final origAlpha = alpha;
    int moveIndex = 0;

    for (final sm in scored) {
      if (_stopped) return 0;

      // Check if capture before making the move
      final isCapture = _game.get(sm.move.toAlgebraic) != null;
      _makeMove(sm.move);
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
        bestMove = sm.uci;
      }

      if (score >= beta) {
        if (ply < _killers.length) {
          _killers[ply][1] = _killers[ply][0];
          _killers[ply][0] = sm.uci;
        }
        _history[sm.uci] = (_history[sm.uci] ?? 0) + depth * depth;
        _tt.store(hash: hash, depth: depth, score: score,
            flag: TTFlag.lowerBound, bestMove: sm.uci);
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

    // Delta pruning: if even winning a queen can't raise alpha, skip
    if (standPat + 900 < alpha) return alpha;

    // Generate all moves and filter for captures
    final moves = _game.generate_moves();
    final captures = <_ScoredCapture>[];
    for (final m in moves) {
      final victim = _game.get(m.toAlgebraic);
      if (victim != null) {
        // MVV-LVA scoring: value victim high, attacker low
        final victimVal = pieceValues[victim.type] ?? 0;
        final attacker = _game.get(m.fromAlgebraic);
        final attackerVal = pieceValues[attacker?.type] ?? 0;
        final score = victimVal * 10 - attackerVal; // MVV-LVA
        captures.add(_ScoredCapture(m, score));
      }
    }

    // Sort by MVV-LVA score (highest first)
    captures.sort((a, b) => b.score - a.score);

    for (final cap in captures) {
      if (_stopped) return 0;

      // SEE-like pruning: skip captures where victim is worth less than attacker
      // and we're already close to alpha (likely losing exchange)
      if (cap.score < 0 && standPat + (pieceValues[_game.get(cap.move.toAlgebraic)?.type] ?? 0) < alpha) {
        continue;
      }

      _makeMove(cap.move);
      _nodes++;
      final score = -_quiescence(-beta, -alpha, ply + 1);
      _game.undo();

      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }

    return alpha;
  }

  /// Fast position hash using FEN's piece placement + turn.
  /// Skips castling/en-passant/move counts for speed while
  /// retaining enough uniqueness for the TT.
  int _quickHash() {
    final fen = _game.fen;
    // Hash only piece placement + turn (first two FEN fields)
    // This is faster than hashing the full FEN string
    final spaceIdx = fen.indexOf(' ');
    if (spaceIdx < 0) return fen.hashCode;
    final secondSpace = fen.indexOf(' ', spaceIdx + 1);
    final key = secondSpace > 0 ? fen.substring(0, secondSpace) : fen;
    return key.hashCode;
  }

  /// Make a move using a reusable map to reduce GC pressure.
  static final Map<String, String?> _moveMap = {'from': '', 'to': '', 'promotion': null};

  void _makeMove(chess.Move move) {
    _moveMap['from'] = move.fromAlgebraic;
    _moveMap['to'] = move.toAlgebraic;
    _moveMap['promotion'] = move.promotion?.name;
    _game.move(_moveMap);
  }

  String _moveToUci(chess.Move move) {
    return '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';
  }

  int _moveScore(chess.Move move, String uci, int ply, String? ttBestMove) {
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

/// Move with pre-computed UCI string and ordering score.
class _ScoredMove {
  final chess.Move move;
  final String uci;
  final int score;
  _ScoredMove(this.move, this.uci, this.score);
}

/// Capture move with MVV-LVA score for quiescence ordering.
class _ScoredCapture {
  final chess.Move move;
  final int score;
  _ScoredCapture(this.move, this.score);
}
