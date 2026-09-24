/// ChessMamba's own search, ported from its search.py (MIT).
///
/// Policy-guided negamax with alpha-beta: at every node only the network's
/// [topK] likeliest moves are tried, captures and promotions are followed in
/// a quiescence search, and leaves are scored by the network's value head.
/// There is no hand-written evaluation anywhere — the search runs entirely on
/// the model's policy and value, as upstream does.
///
/// Every node costs one model step, so the search is only as deep as the
/// backend is fast: a few plies on native ONNX Runtime, policy-only on the
/// pure-Dart interpreter.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;

import 'step_model.dart';

/// A position the search has reached: the model's output after its last
/// move, which also carries the state for the next step.
class MambaNode {
  final MambaOutput output;
  final int ply;
  const MambaNode(this.output, this.ply);
}

/// Square index as the model numbers it: a1 = 0 .. h8 = 63.
int mambaSquare(String algebraic) =>
    (algebraic.codeUnitAt(0) - 97) + 8 * (algebraic.codeUnitAt(1) - 49);

String _uci(chess.Move m) =>
    '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';

class MambaSearchResult {
  final String? bestMove;

  /// Value of [bestMove] for the side to move, -1..1.
  final double score;
  final int depth;
  const MambaSearchResult(this.bestMove, this.score, this.depth);
}

class MambaSearcher {
  final MambaStepModel model;
  final int topK;
  final int maxDepth;
  final int maxQDepth;
  final int qsTopK;

  late Stopwatch _clock;
  late Duration _budget;
  bool Function()? _shouldStop;

  MambaSearcher(
    this.model, {
    this.topK = 10,
    this.maxDepth = 6,
    this.maxQDepth = 6,
    this.qsTopK = 6,
  });

  bool get _outOfTime =>
      _clock.elapsed > _budget || (_shouldStop?.call() ?? false);

  /// The model's steps after each of [moves] from [node], in one batch.
  ///
  /// A cutoff may leave later children unused, but a batch of ten costs
  /// about as much as 1.4 single steps, so expanding all of them up front is
  /// still far cheaper than one at a time.
  Future<List<MambaNode>> expandAll(
      MambaNode node, List<chess.Move> moves) async {
    if (moves.isEmpty) return const [];
    final outs = await model.stepBatch([
      for (final m in moves)
        MambaStepInput(
          from: mambaSquare(m.fromAlgebraic),
          to: mambaSquare(m.toAlgebraic),
          promo: mambaPromoIndex[m.promotion?.name] ?? 0,
          ply: math.min(node.ply + 1, mambaMaxPlies),
          start: false,
          state: node.output.state,
        ),
    ]);
    return [for (final o in outs) MambaNode(o, node.ply + 1)];
  }

  static bool _isDraw(chess.Chess board) =>
      board.in_stalemate ||
      board.insufficient_material ||
      board.in_threefold_repetition ||
      board.half_moves >= 100;

  /// Legal moves with the network's prior, likeliest first.
  static List<(chess.Move, double)> priors(chess.Chess board, MambaNode node) {
    final legal = board.generate_moves();
    if (legal.isEmpty) return const [];
    final pol = node.output.policy, pro = node.output.promo;
    final scores = [
      for (final m in legal)
        pol[mambaSquare(m.fromAlgebraic) * 64 + mambaSquare(m.toAlgebraic)] +
            (m.promotion == null
                ? 0.0
                : pro[mambaPromoIndex[m.promotion!.name] ?? 0]),
    ];
    final top = scores.reduce(math.max);
    final exps = [for (final s in scores) math.exp(s - top)];
    final total = exps.fold(0.0, (a, b) => a + b);
    final out = [
      for (var i = 0; i < legal.length; i++) (legal[i], exps[i] / total)
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  Future<double> _quiescence(chess.Chess board, MambaNode node, double alpha,
      double beta, int qdepth) async {
    if (board.in_checkmate) return -1;
    if (_isDraw(board)) return 0;
    final standPat = node.output.value;
    if (_outOfTime || qdepth >= maxQDepth) return standPat;
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;
    final loud = [
      for (final p in priors(board, node))
        if (p.$1.captured != null || p.$1.promotion != null) p.$1
    ];
    final tried = loud.take(qsTopK).toList();
    final children = await expandAll(node, tried);
    for (var i = 0; i < tried.length; i++) {
      final mv = tried[i], child = children[i];
      board.make_move(mv);
      final score =
          -await _quiescence(board, child, -beta, -alpha, qdepth + 1);
      board.undo_move();
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
      if (_outOfTime) break;
    }
    return alpha;
  }

  Future<double> _negamax(chess.Chess board, MambaNode node, int depth,
      double alpha, double beta) async {
    if (board.in_checkmate) return -1;
    if (_isDraw(board)) return 0;
    if (_outOfTime) return node.output.value;
    if (depth == 0) return _quiescence(board, node, alpha, beta, 0);
    final ranked = [for (final p in priors(board, node).take(topK)) p.$1];
    final children = await expandAll(node, ranked);
    var best = double.negativeInfinity;
    for (var i = 0; i < ranked.length; i++) {
      final mv = ranked[i], child = children[i];
      board.make_move(mv);
      final score = -await _negamax(board, child, depth - 1, -beta, -alpha);
      board.undo_move();
      if (score > best) best = score;
      if (best > alpha) alpha = best;
      if (alpha >= beta || _outOfTime) break;
    }
    return best;
  }

  /// Iterative deepening from [root] (the model's output for [board]) within
  /// [budget]. [policyOnly] returns the likeliest legal move without search.
  /// [onDepth] is told each completed iteration.
  Future<MambaSearchResult> search(
    chess.Chess board,
    MambaNode root, {
    required Duration budget,
    bool policyOnly = false,
    int? depthLimit,
    void Function(MambaSearchResult)? onDepth,
    bool Function()? shouldStop,
  }) async {
    _clock = Stopwatch()..start();
    _budget = budget;
    _shouldStop = shouldStop;
    final ranked = priors(board, root).take(topK).toList();
    if (ranked.isEmpty) return MambaSearchResult(null, root.output.value, 0);
    var best = MambaSearchResult(_uci(ranked.first.$1), root.output.value, 0);
    if (policyOnly) return best;

    final limit = math.min(depthLimit ?? maxDepth, maxDepth);
    final rootMoves = [for (final r in ranked) r.$1];
    final rootChildren = await expandAll(root, rootMoves);
    for (var depth = 1; depth <= limit && !_outOfTime; depth++) {
      var alpha = double.negativeInfinity;
      const beta = double.infinity;
      chess.Move? iterBest;
      var iterScore = double.negativeInfinity;
      for (var i = 0; i < rootMoves.length; i++) {
        final mv = rootMoves[i], child = rootChildren[i];
        board.make_move(mv);
        final score = -await _negamax(board, child, depth - 1, -beta, -alpha);
        board.undo_move();
        if (score > iterScore) {
          iterScore = score;
          iterBest = mv;
        }
        if (score > alpha) alpha = score;
        if (_outOfTime) break;
      }
      // An iteration cut short by the clock is not trusted, as upstream.
      if (iterBest != null && !_outOfTime) {
        best = MambaSearchResult(_uci(iterBest), iterScore, depth);
        onDepth?.call(best);
      }
    }
    return best;
  }
}

/// Zero state for the first step.
Float32List mambaZeroState() => Float32List(mambaStateSize);
