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
import 'dart:typed_data';

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

  /// How much of the game to replay for the network. Eight positions become
  /// history planes; the rest are there so the repetition plane can tell
  /// whether a position had occurred before, which under the fifty-move rule
  /// can be a hundred plies back.
  static const int _historyLimit = 129;

  /// Isolate workers for the matmul pool. The network is small, so a handful is
  /// plenty; 0 or 1 disables the pool.
  final int isolateWorkers;

  OnnxModel? _model;
  final NnEvalCache _evaluationCache = NnEvalCache();
  int? _estimatedEvaluationMicros;

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
      final played =
          fenHistoryFromPositionCommand(positionCommand, limit: _historyLimit);
      final fen = played.last;
      final history = played.sublist(0, played.length - 1);
      final board = chess.Chess.fromFEN(fen);
      final legalMoves = _legalMoves(board);

      if (legalMoves.isEmpty) {
        _stateNotifier.value = EngineState.ready;
        throw StateError('No legal moves');
      }
      if (legalMoves.length == 1) {
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
        evaluate: _evaluateCached,
        evaluateBatch: _evaluateBatch,
        batchSize: 4,
        estimatedEvaluationMicros: _estimatedEvaluationMicros,
        historyFens: history,
        positionAt: (moves) => _positionAt(fen, history, moves),
        config: config,
      );

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
      final played =
          fenHistoryFromPositionCommand(positionCommand, limit: _historyLimit);
      final fen = played.last;
      final board = chess.Chess.fromFEN(fen);
      final legalMoves = _legalMoves(board);
      if (legalMoves.isEmpty) return;

      final eval = await _evaluateCached(
          fen, legalMoves, played.sublist(0, played.length - 1));
      // The network reports a win probability, not centipawns. Map it onto a
      // pawn-ish scale so the eval bar means roughly the same thing it does for
      // the search engines.
      final best =
          eval.policy.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
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
  MctsPosition _positionAt(
      String rootFen, List<String> rootHistory, List<String> moves) {
    final board = chess.Chess.fromFEN(rootFen);
    // The network reads the previous plies, so a leaf needs the line that
    // reached it — the root's own history, then the root, then each position
    // along the way. Handing every leaf the root's history instead describes
    // a game that diverged several moves ago.
    final history = <String>[...rootHistory, rootFen];
    for (final uci in moves) {
      board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        if (uci.length > 4) 'promotion': uci.substring(4, 5),
      });
      history.add(board.fen);
    }
    history.removeLast(); // the leaf itself is not part of its own history
    final legal = _legalMovesOf(board);
    if (legal.isEmpty) {
      // Mate is a loss for the side to move; stalemate is a draw.
      return MctsPosition(
        fen: board.fen,
        legalMoves: const [],
        historyFens: history,
        terminalValue: board.in_check ? -1.0 : 0.0,
      );
    }
    if (board.in_draw || board.in_threefold_repetition) {
      return MctsPosition(
          fen: board.fen,
          legalMoves: legal,
          historyFens: history,
          terminalValue: 0.0);
    }
    return MctsPosition(
        fen: board.fen, legalMoves: legal, historyFens: history);
  }

  List<String> _legalMovesOf(chess.Chess board) => _legalMoves(board);

  List<String> _legalMoves(chess.Chess board) => [
        for (final m in board.generate_moves())
          '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
      ];

  /// One network evaluation: policy over the legal moves plus a value in
  /// [-1, 1] from the side to move's perspective.
  Future<NnEval> _evaluatePosition(
      String fen, List<String> legalMoves, List<String> history) async {
    final model = _model!;
    final planes = encodePosition(fen, historyFens: history);
    final watch = Stopwatch()..start();
    final out = await model.runAsync(
      {
        '/input/planes': Tensor.float(planes, [1, 112, 8, 8])
      },
      ['/output/policy', '/output/wdl'],
    );
    watch.stop();
    _recordEvaluationCost(watch.elapsedMicroseconds);

    return _decodeEvaluation(
        fen, legalMoves, out['/output/policy']!.f!, out['/output/wdl']!.f!);
  }

  Future<List<NnEval>> _evaluateBatch(List<MctsPosition> positions) async {
    final results = List<NnEval?>.filled(positions.length, null);
    final misses = <MctsPosition>[];
    final missIndices = <int>[];
    for (var i = 0; i < positions.length; i++) {
      final position = positions[i];
      final cached = _evaluationCache.lookup(
          position.fen, position.legalMoves, position.historyFens);
      if (cached == null) {
        misses.add(position);
        missIndices.add(i);
      } else {
        results[i] = await cached;
      }
    }
    if (misses.isEmpty) return results.cast<NnEval>();

    final planes = Float32List(misses.length * 112 * 8 * 8);
    for (var i = 0; i < misses.length; i++) {
      planes.setRange(i * 112 * 8 * 8, (i + 1) * 112 * 8 * 8,
          encodePosition(misses[i].fen, historyFens: misses[i].historyFens));
    }
    final watch = Stopwatch()..start();
    final out = await _model!.runAsync(
      {
        '/input/planes': Tensor.float(planes, [misses.length, 112, 8, 8])
      },
      ['/output/policy', '/output/wdl'],
    );
    watch.stop();
    _recordEvaluationCost(
        (watch.elapsedMicroseconds / (0.5 + 0.5 * misses.length)).round());
    final policies = out['/output/policy']!.f!;
    final wdls = out['/output/wdl']!.f!;
    for (var i = 0; i < misses.length; i++) {
      final position = misses[i];
      final evaluation = _decodeEvaluation(
          position.fen,
          position.legalMoves,
          Float32List.sublistView(policies, i * 1858, (i + 1) * 1858),
          Float32List.sublistView(wdls, i * 3, (i + 1) * 3));
      results[missIndices[i]] = evaluation;
      _evaluationCache.store(
          position.fen, position.legalMoves, position.historyFens, evaluation);
    }
    return results.cast<NnEval>();
  }

  NnEval _decodeEvaluation(String fen, List<String> legalMoves,
      Float32List policyLogits, Float32List wdl) {
    final board = chess.Chess.fromFEN(fen);
    final isBlack = board.turn == chess.Color.BLACK;
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

  void _recordEvaluationCost(int micros) {
    final previous = _estimatedEvaluationMicros;
    _estimatedEvaluationMicros =
        previous == null ? micros : (previous * 0.25 + micros * 0.75).round();
  }

  Future<NnEval> _evaluateCached(
          String fen, List<String> legalMoves, List<String> history) =>
      _evaluationCache.evaluate(fen, legalMoves, history, _evaluatePosition);

  @override
  void stop() {
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _evaluationCache.clear();
    _model?.dispose();
    _model = null;
    _stateNotifier.value = EngineState.disposed;
  }
}
