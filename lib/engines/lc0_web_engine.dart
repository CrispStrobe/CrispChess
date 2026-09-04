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

  /// How much of the game to replay for the network. Eight positions become
  /// history planes; the rest are there so the repetition plane can tell
  /// whether a position had occurred before, which under the fifty-move rule
  /// can be a hundred plies back.
  static const int _historyLimit = 129;

  bool _modelLoaded = false;
  final NnEvalCache _evaluationCache = NnEvalCache();

  Lc0Engine({String? variantId}) : variantId = variantId ?? defaultLc0Variant;

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

  // MCTS drives ONNX inference on the UI thread; running it in the background
  // competes with the very frames it would be hiding behind.
  @override
  bool get canPonder => false;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final variant = getLc0Variant(variantId);
      debugPrint(
          '[Lc0/Web] Loading ${variant.displayName} from ${variant.url}');
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
      final played =
          fenHistoryFromPositionCommand(positionCommand, limit: _historyLimit);
      final fen = played.last;
      final history = played.sublist(0, played.length - 1);
      final board = chess.Chess.fromFEN(fen);

      // Get legal moves as UCI strings
      final legalMoveObjs = board.moves({'asObjects': true});
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
        evaluate: _evaluateCached,
        historyFens: history,
        positionAt: (moves) => _positionAt(fen, history, moves),
        config: config,
      );

      _stateNotifier.value = EngineState.ready;
      return bestUci;
    } catch (e) {
      debugPrint('[Lc0/Web] bestMove failed: $e');
      _stateNotifier.value = EngineState.ready;
      rethrow;
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
    final legal = [
      for (final m in board.generate_moves())
        '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
    ];
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

  /// Evaluate a position using the neural network.
  /// Returns policy probabilities for legal moves and a value estimate.
  Future<NnEval> _evaluatePosition(
      String fen, List<String> legalMoves, List<String> history) async {
    final board = chess.Chess.fromFEN(fen);
    final isBlack = board.turn == chess.Color.BLACK;

    // Encode position into 112 planes
    final inputPlanes = encodePosition(fen, historyFens: history);

    // Run ONNX inference
    final combined = (await _jsLc0Infer(inputPlanes.toJS).toDart).toDart;

    // Split output: [policy(1858), wdl(3)]
    final policyLogits = Float32List.sublistView(combined, 0, 1858);
    final wdl = Float32List.sublistView(combined, 1858, 1861);

    // WDL order: [win, draw, loss], already probabilities — the exported
    // graph ends in a Softmax feeding /output/wdl. Running another softmax
    // over three numbers that already sum to one squeezes the value from
    // [-1, 1] into about [-0.36, 0.36], so a certain win read as a small
    // edge and the search was very nearly value-blind.
    final value = wdl[0] - wdl[2]; // win - loss

    // Build policy map for legal moves
    final moveToIndex = policy.getMoveToIndex();
    final policyMap = <String, double>{};

    // Collect logits for legal moves, apply softmax over legal moves only
    double maxLogit = double.negativeInfinity;
    final legalLogits = <double>[];

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
        debugPrint(
            '[Lc0/Web] Move not in policy map: $move (lookup: $lookupMove)');
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

  Future<NnEval> _evaluateCached(
          String fen, List<String> legalMoves, List<String> history) =>
      _evaluationCache.evaluate(fen, legalMoves, history, _evaluatePosition);

  /// Softmax for 3 values, returns [p0, p1, p2].

  @override
  Stream<EvalInfo> analyze(String positionCommand,
      {int? depth, bool infinite = false}) async* {
    if (!_modelLoaded) return;
    _stateNotifier.value = EngineState.thinking;

    try {
      final played =
          fenHistoryFromPositionCommand(positionCommand, limit: _historyLimit);
      final fen = played.last;
      final board = chess.Chess.fromFEN(fen);
      final isBlack = board.turn == chess.Color.BLACK;

      // Encode and run inference
      final inputPlanes = encodePosition(fen,
          historyFens: played.sublist(0, played.length - 1));
      final combined = (await _jsLc0Infer(inputPlanes.toJS).toDart).toDart;

      final wdl = Float32List.sublistView(combined, 1858, 1861);
      // Already probabilities; see _evaluatePosition.
      // Value from white's perspective for display
      double whiteWinProb = isBlack ? wdl[2] : wdl[0];
      double whiteLossProb = isBlack ? wdl[0] : wdl[2];
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
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _evaluationCache.clear();
    _modelLoaded = false;
    try {
      _jsLc0Close().toDart;
    } catch (_) {}
    _stateNotifier.value = EngineState.disposed;
  }
}
