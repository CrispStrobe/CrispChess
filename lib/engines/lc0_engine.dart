/// Lc0 engine — native version.
///
/// The same engine the web build runs, with the one platform-specific piece
/// swapped out: lc0-style 112-plane board encoding, Maia neural-network weights
/// and MCTS, with inference on the pure-Dart ONNX interpreter
/// (`package:onnx_runtime_dart`) instead of onnxruntime-web.
///
/// This replaces a stub that had reported `isAvailable => false` since the
/// engine was first added: the original plan was to link the `leela_chess_zero`
/// package, which compiles lc0's C++ and would have made the whole app
/// GPL-3.0. Nothing needs linking — the search here is this app's own Dart
/// MCTS, and the weights are downloaded at run time as data, the same
/// arrangement the Stockfish builds use. See THIRD_PARTY_LICENSES.md for the
/// provenance of the policy-map table and the weights.
library;

import 'dart:async';
import 'dart:math';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import 'chess_engine.dart';
import 'lc0_dart/encoding.dart';
import 'lc0_dart/mcts.dart';
import 'lc0_dart/policy_map.dart' as policy;
import 'lc0_dart/variants.dart';
import 'maia3_dart/onnx/model_fetch.dart';
import 'uci_position.dart';

/// Lc0 for native platforms — MCTS over a Maia network.
class Lc0Engine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final String variantId;

  /// The positions leading up to the current one; the encoding feeds the last
  /// seven to the network as history planes.
  final List<String> _fenHistory = [];

  /// Isolate workers for the matmul pool. The network is small, so a handful is
  /// plenty; 0 or 1 disables the pool.
  final int isolateWorkers;

  OnnxModel? _model;

  Lc0Engine({String? variantId, this.isolateWorkers = 4})
      : variantId = variantId ?? defaultLc0Variant;

  @override
  String get name {
    final v = getLc0Variant(variantId);
    return 'Lc0 (${v.displayName})';
  }

  @override
  String get version => '1.0';
  @override
  String get license => 'GPL-3.0 weights (downloaded, not linked)';
  @override
  int get estimatedElo => getLc0Variant(variantId).estimatedElo;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // Inference runs on the calling isolate (with a matmul pool behind it), so a
  // background search would compete with the frames it is meant to hide behind.
  @override
  bool get canPonder => false;

  static bool get isAvailable => !kIsWeb;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final variant = getLc0Variant(variantId);
      debugPrint('[Lc0] Loading ${variant.displayName} from ${variant.url}');
      final bytes = await fetchModelBytes(variant.url, '${variant.id}.onnx');
      final model = OnnxModel.fromBytes(bytes);
      if (isolateWorkers > 1) {
        await model.parallelize(workers: isolateWorkers);
      }
      _model = model;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Lc0] Ready (${variant.displayName}, '
          '~${variant.estimatedElo} ELO)');
    } catch (e) {
      debugPrint('[Lc0] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_model == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    try {
      final fen = fenFromPositionCommand(positionCommand);
      final board = chess.Chess.fromFEN(fen);
      final legalMoves = _legalMoves(board);

      if (legalMoves.isEmpty) {
        _stateNotifier.value = EngineState.ready;
        throw StateError('No legal moves');
      }
      if (legalMoves.length == 1) {
        _rememberPosition(fen);
        _stateNotifier.value = EngineState.ready;
        return legalMoves.first;
      }

      final config = MctsConfig(
        maxNodes: skillLevel != null
            ? (50 + skillLevel * skillLevel * 2).clamp(50, 800)
            : 200,
        maxTime: moveTime ?? const Duration(seconds: 5),
        cpuct: skillLevel != null ? 2.5 + (20 - skillLevel) * 0.2 : 2.5,
      );

      final best = await mctsSearch(
        fen: fen,
        legalMoves: legalMoves,
        evaluate: _evaluatePosition,
        positionAt: (moves) => _positionAt(fen, moves),
        config: config,
      );

      _rememberPosition(fen);
      _stateNotifier.value = EngineState.ready;
      return best;
    } catch (e) {
      debugPrint('[Lc0] bestMove failed: $e');
      _stateNotifier.value = EngineState.ready;
      rethrow;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand,
      {int? depth, bool infinite = false}) async* {
    if (_model == null) return;
    _stateNotifier.value = EngineState.thinking;
    try {
      final fen = fenFromPositionCommand(positionCommand);
      final board = chess.Chess.fromFEN(fen);
      final legalMoves = _legalMoves(board);
      if (legalMoves.isEmpty) return;

      final eval = await _evaluatePosition(fen, legalMoves);
      // The network reports a win probability, not centipawns. Map it onto a
      // pawn-ish scale so the eval bar means roughly the same thing it does for
      // the search engines.
      final best = eval.policy.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      yield EvalInfo(score: eval.value * 5.0, depth: 1, bestMove: best);
    } catch (e) {
      debugPrint('[Lc0] analyze failed: $e');
    } finally {
      _stateNotifier.value = EngineState.ready;
    }
  }


  /// Resolves the position a line of play reaches, so MCTS can evaluate more
  /// than the root. Replays from the search root each time: the lines are a
  /// handful of plies and this runs once per simulation, against a network
  /// evaluation that costs orders of magnitude more.
  MctsPosition _positionAt(String rootFen, List<String> moves) {
    final board = chess.Chess.fromFEN(rootFen);
    for (final uci in moves) {
      board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        if (uci.length > 4) 'promotion': uci.substring(4, 5),
      });
    }
    final legal = _legalMovesOf(board);
    if (legal.isEmpty) {
      // Mate is a loss for the side to move; stalemate is a draw.
      return MctsPosition(
        fen: board.fen,
        legalMoves: const [],
        terminalValue: board.in_check ? -1.0 : 0.0,
      );
    }
    if (board.in_draw || board.in_threefold_repetition) {
      return MctsPosition(fen: board.fen, legalMoves: legal, terminalValue: 0.0);
    }
    return MctsPosition(fen: board.fen, legalMoves: legal);
  }

  List<String> _legalMovesOf(chess.Chess board) => _legalMoves(board);

  List<String> _legalMoves(chess.Chess board) => [
        for (final m in board.generate_moves())
          '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
      ];

  void _rememberPosition(String fen) {
    _fenHistory.add(fen);
    // Eight of these become history planes, but the repetition plane asks
    // whether a position had occurred *before*, and a repetition can be up
    // to a hundred plies apart under the fifty-move rule. Keeping only the
    // eight the planes use answers that question wrong.
    if (_fenHistory.length > 128) _fenHistory.removeAt(0);
  }

  /// One network evaluation: policy over the legal moves plus a value in
  /// [-1, 1] from the side to move's perspective.
  Future<NnEval> _evaluatePosition(String fen, List<String> legalMoves) async {
    final model = _model!;
    final board = chess.Chess.fromFEN(fen);
    final isBlack = board.turn == chess.Color.BLACK;

    final planes = encodePosition(fen, historyFens: _fenHistory);
    final out = await model.runAsync(
      {'/input/planes': Tensor.float(planes, [1, 112, 8, 8])},
      ['/output/policy', '/output/wdl'],
    );

    // lc0's own exporter emits the policy already in move-vocabulary order and
    // the WDL already as a distribution, so neither needs post-processing here.
    final policyLogits = out['/output/policy']!.f!;
    final wdl = out['/output/wdl']!.f!;
    final value = wdl[0] - wdl[2]; // win - loss

    // Softmax over the legal moves only.
    final moveToIndex = policy.getMoveToIndex();
    final logits = <double>[];
    var maxLogit = double.negativeInfinity;
    for (final move in legalMoves) {
      // Policy indices are always from white's point of view.
      final lookup = isBlack ? policy.mirrorMove(move) : move;
      final idx = moveToIndex[lookup];
      final logit = idx != null ? policyLogits[idx].toDouble() : -100.0;
      logits.add(logit);
      if (logit > maxLogit) maxLogit = logit;
    }

    var sum = 0.0;
    final weights = <double>[];
    for (final logit in logits) {
      final w = exp(logit - maxLogit);
      weights.add(w);
      sum += w;
    }

    final probabilities = <String, double>{};
    for (var i = 0; i < legalMoves.length; i++) {
      probabilities[legalMoves[i]] = weights[i] / sum;
    }
    return NnEval(policy: probabilities, value: value);
  }

  @override
  void stop() {
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _model?.dispose();
    _model = null;
    _stateNotifier.value = EngineState.disposed;
  }
}
