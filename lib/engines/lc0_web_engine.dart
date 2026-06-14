/// Lc0 engine — web version.
///
/// Uses Maia ONNX weights with lc0-style 112-plane board encoding
/// and MCTS search. ONNX inference runs via onnxruntime-web through
/// a thin JS bridge (web/lc0_onnx_bridge.js).
///
/// License: GPL-3.0 (weights downloaded separately, not linked).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'chess_engine.dart';
import 'lc0_dart/encoding.dart';
import 'lc0_dart/mcts.dart';
import 'lc0_dart/policy_map.dart' as policy;
import 'lc0_dart/variants.dart';
import 'uci_position.dart';

// JS bridge functions (defined in web/lc0_onnx_bridge.js)
@JS('lc0OnnxLoad')
external JSPromise<JSAny?> _jsLc0Load(JSString modelUrl);

// Returns Float32Array of 1861 elements: [policy(1858), wdl(3)]
@JS('lc0OnnxInfer')
external JSPromise<JSFloat32Array> _jsLc0Infer(JSFloat32Array inputPlanes);

@JS('lc0OnnxClose')
external JSPromise<JSAny?> _jsLc0Close();

/// Lc0 engine for web — MCTS + neural network via ONNX Runtime Web.
class Lc0Engine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final String variantId;
  final List<String> _fenHistory = [];

  bool _modelLoaded = false;

  Lc0Engine({String? variantId})
      : variantId = variantId ?? defaultLc0Variant;

  @override
  String get name {
    final v = getLc0Variant(variantId);
    return 'Lc0 (${v.displayName})';
  }

  @override
  String get version => '1.0-web';
  @override
  String get license => 'GPL-3.0';
  @override
  int get estimatedElo => getLc0Variant(variantId).estimatedElo;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final variant = getLc0Variant(variantId);
      debugPrint('[Lc0/Web] Loading ${variant.displayName} from ${variant.url}');
      await _jsLc0Load(variant.url.toJS).toDart;
      _modelLoaded = true;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Lc0/Web] Ready');
    } catch (e) {
      debugPrint('[Lc0/Web] Init failed: $e');
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
    if (!_modelLoaded) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    try {
      final fen = fenFromPositionCommand(positionCommand);
      final board = chess.Chess.fromFEN(fen);
      final isBlack = board.turn == chess.Color.BLACK;

      // Get legal moves as UCI strings
      final legalMoveObjs = board.moves({'asObjects': true}) as List;
      final legalMoves = <String>[];
      for (final m in legalMoveObjs) {
        String uci = '${m.fromAlgebraic}${m.toAlgebraic}';
        if (m.promotion != null) {
          uci += m.promotion.toString().toLowerCase();
        }
        legalMoves.add(uci);
      }

      if (legalMoves.isEmpty) {
        _stateNotifier.value = EngineState.ready;
        throw StateError('No legal moves');
      }

      if (legalMoves.length == 1) {
        _fenHistory.add(fen);
        _stateNotifier.value = EngineState.ready;
        return legalMoves.first;
      }

      // Configure MCTS based on skill level
      final config = MctsConfig(
        maxNodes: skillLevel != null
            ? (50 + skillLevel * skillLevel * 2).clamp(50, 800)
            : 200,
        maxTime: moveTime ?? const Duration(seconds: 5),
        cpuct: skillLevel != null ? 2.5 + (20 - skillLevel) * 0.2 : 2.5,
      );

      // Run MCTS search with neural network evaluation
      final bestUci = await mctsSearch(
        fen: fen,
        legalMoves: legalMoves,
        evaluate: (evalFen, evalLegalMoves) =>
            _evaluatePosition(evalFen, evalLegalMoves),
        config: config,
      );

      _fenHistory.add(fen);
      if (_fenHistory.length > 8) _fenHistory.removeAt(0);

      _stateNotifier.value = EngineState.ready;
      return bestUci;
    } catch (e) {
      debugPrint('[Lc0/Web] bestMove failed: $e');
      _stateNotifier.value = EngineState.ready;
      rethrow;
    }
  }

  /// Evaluate a position using the neural network.
  /// Returns policy probabilities for legal moves and a value estimate.
  Future<NnEval> _evaluatePosition(
      String fen, List<String> legalMoves) async {
    final board = chess.Chess.fromFEN(fen);
    final isBlack = board.turn == chess.Color.BLACK;

    // Encode position into 112 planes
    final inputPlanes = encodePosition(fen, historyFens: _fenHistory);

    // Run ONNX inference
    final combined = (await _jsLc0Infer(inputPlanes.toJS).toDart).toDart;

    // Split output: [policy(1858), wdl(3)]
    final policyLogits = Float32List.sublistView(combined, 0, 1858);
    final wdl = Float32List.sublistView(combined, 1858, 1861);

    // Convert WDL to value [-1, 1] from current player's perspective
    // WDL order: [win, draw, loss]
    final wdlSum = _softmax3(wdl[0], wdl[1], wdl[2]);
    final value = wdlSum[0] - wdlSum[2]; // win - loss

    // Build policy map for legal moves
    final moveToIndex = policy.getMoveToIndex();
    final policyMap = <String, double>{};

    // Collect logits for legal moves, apply softmax over legal moves only
    double maxLogit = double.negativeInfinity;
    final legalLogits = <double>[];
    final legalIndices = <int>[];

    for (final move in legalMoves) {
      // Mirror move for black (policy indices assume white's perspective)
      final lookupMove = isBlack ? policy.mirrorMove(move) : move;
      final idx = moveToIndex[lookupMove];

      double logit;
      if (idx != null) {
        logit = policyLogits[idx];
      } else {
        // Move not in policy map (shouldn't happen for standard chess)
        logit = -100.0;
        debugPrint('[Lc0/Web] Move not in policy map: $move (lookup: $lookupMove)');
      }

      legalLogits.add(logit);
      if (logit > maxLogit) maxLogit = logit;
    }

    // Softmax over legal moves
    double expSum = 0;
    final expLogits = <double>[];
    for (final logit in legalLogits) {
      final e = exp(logit - maxLogit);
      expLogits.add(e);
      expSum += e;
    }

    for (int i = 0; i < legalMoves.length; i++) {
      policyMap[legalMoves[i]] = expLogits[i] / expSum;
    }

    return NnEval(policy: policyMap, value: value);
  }

  /// Softmax for 3 values, returns [p0, p1, p2].
  List<double> _softmax3(double a, double b, double c) {
    final m = [a, b, c].reduce(max);
    final ea = exp(a - m);
    final eb = exp(b - m);
    final ec = exp(c - m);
    final s = ea + eb + ec;
    return [ea / s, eb / s, ec / s];
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {
    if (!_modelLoaded) return;
    _stateNotifier.value = EngineState.thinking;

    try {
      final fen = fenFromPositionCommand(positionCommand);
      final board = chess.Chess.fromFEN(fen);
      final isBlack = board.turn == chess.Color.BLACK;

      // Encode and run inference
      final inputPlanes = encodePosition(fen, historyFens: _fenHistory);
      final combined = (await _jsLc0Infer(inputPlanes.toJS).toDart).toDart;

      final wdl = Float32List.sublistView(combined, 1858, 1861);
      final wdlProbs = _softmax3(wdl[0], wdl[1], wdl[2]);

      // Value from white's perspective for display
      double whiteWinProb = isBlack ? wdlProbs[2] : wdlProbs[0];
      double whiteLossProb = isBlack ? wdlProbs[0] : wdlProbs[2];
      final score = (whiteWinProb - whiteLossProb) * 5.0; // Scale to ~pawns

      yield EvalInfo(score: score, depth: 1, bestMove: null);
    } catch (e) {
      debugPrint('[Lc0/Web] Analysis error: $e');
    }

    _stateNotifier.value = EngineState.ready;
  }

  @override
  void stop() {
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void dispose() {
    _modelLoaded = false;
    _fenHistory.clear();
    try {
      _jsLc0Close().toDart;
    } catch (_) {}
    _stateNotifier.value = EngineState.disposed;
  }
}
