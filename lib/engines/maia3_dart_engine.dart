/// Maia3 Dart engine — pure Dart port of maia3-js.
///
/// All tokenization, move vocabulary, sampling, *and* ONNX inference are
/// pure Dart — one implementation for every platform (see
/// maia3_dart/onnx_model_dart.dart and maia3_dart/onnx/).
///
/// License: MIT (port of maia3-js MIT code).

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:chess/chess.dart' as chess_lib;

import 'chess_engine.dart';
import 'maia3_dart/encoding.dart';
import 'maia3_dart/history.dart';
import 'maia3_dart/moves.dart' as moves;
import 'maia3_dart/onnx_model.dart';
import 'maia3_dart/onnx_model_dart.dart';
import 'maia3_dart/onnx_runtime_backend.dart';
import 'maia3_dart/utils.dart';
import 'maia3_dart/variants.dart';
import 'uci_position.dart';

/// Maia3 engine with all logic in Dart + platform ONNX inference.
class Maia3DartEngine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final String variantId;
  final int playerElo;
  final double temperature;
  final double topP;

  Maia3OnnxModel? _model;

  /// Backend selector. The default is the onnx_runtime_dart `OnnxModel`
  /// backend (isolate-pooled + batched). Flip to true to fall back to the
  /// legacy direct-executor wiring in maia3_dart/onnx_model_dart.dart, kept
  /// as the parity oracle (test/maia3_runtime_parity_test.dart).
  static bool useLegacyBackend = false;

  Maia3DartEngine({
    this.variantId = defaultVariant,
    this.playerElo = 1500,
    this.temperature = 0.0,
    this.topP = 1.0,
  });

  @override
  String get name => 'Maia3 Dart';
  @override
  String get version => '1.0';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => playerElo;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final variant = getVariant(variantId);
      _model = useLegacyBackend
          ? Maia3DartOnnxModel(variant: variant)
          : Maia3OnnxRuntimeBackend(variant: variant);
      await _model!.load();
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Maia3Dart] Ready (${variant.displayName})');
    } catch (e) {
      debugPrint('[Maia3Dart] Init failed: $e');
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
      // Real, consecutive game history straight from the position command —
      // maia3-js conditions on it, and it must not be reconstructed from the
      // engine's own turns (that skips every other ply).
      final history = _historyFor(positionCommand);
      final fen = history.last;
      final selfElo = skillLevel != null
          ? (800 + (skillLevel * 60)).clamp(0, 5000)
          : playerElo.clamp(0, 5000);
      final oppoElo = selfElo; // maia3-js defaults oppoElo to selfElo

      final boards = resolveHistory(_historyInput(history));
      final tokens = buildHistoryTokens(boards);

      // Run inference
      final result = await _model!.infer(tokens, selfElo, oppoElo);

      // Build legal move mask
      final board = chess_lib.Chess.fromFEN(fen);
      final isBlack = fen.split(' ').length > 1 && fen.split(' ')[1] == 'b';
      final legalMoves = board.moves({'asObjects': true}) as List;

      final mask = Uint8List(moves.numMoves);
      final moveIndex = moves.getMoveToIndex();

      for (final m in legalMoves) {
        String uci = '${m.fromAlgebraic}${m.toAlgebraic}';
        if (m.promotion != null) {
          uci += m.promotion.toString().toLowerCase();
        }

        // If black to move, mirror the UCI for lookup (model always sees white POV)
        final lookupUci = isBlack ? mirrorMove(uci) : uci;
        final idx = moveIndex[lookupUci];
        if (idx != null) mask[idx] = 1;
      }

      // Apply temperature scaling
      final logits = result.logitsMove;
      if (temperature > 0) {
        for (int i = 0; i < logits.length; i++) {
          logits[i] /= temperature;
        }
      }

      // Masked softmax
      final probs = softmax(logits, mask: mask);

      // Select move
      int moveIdx;
      if (temperature == 0) {
        moveIdx = argmax(probs);
      } else {
        moveIdx = sampleIndex(probs, topP: topP);
      }

      // Convert back to UCI
      String bestUci = moves.indexToMove(moveIdx);
      if (isBlack) bestUci = mirrorMove(bestUci);

      _stateNotifier.value = EngineState.ready;
      return bestUci;
    } catch (e) {
      debugPrint('[Maia3Dart] Prediction failed: $e');
      _stateNotifier.value = EngineState.ready;
      rethrow;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {
    // Maia3 provides WDL, not depth-based eval
    if (_model == null) return;
    _stateNotifier.value = EngineState.thinking;

    try {
      final history = _historyFor(positionCommand);
      final selfElo = playerElo.clamp(0, 5000);
      final boards = resolveHistory(_historyInput(history));
      final tokens = buildHistoryTokens(boards);
      final result = await _model!.infer(tokens, selfElo, selfElo);

      final wdl = wdlFromValueLogits([
        result.logitsValue[0].toDouble(),
        result.logitsValue[1].toDouble(),
        result.logitsValue[2].toDouble(),
      ]);
      final winProb = winProbabilityFromWdl(wdl);
      // Convert to centipawn-like score
      final score = (winProb - 0.5) * 10.0;

      yield EvalInfo(score: score, depth: 1, bestMove: null);
    } catch (e) {
      debugPrint('[Maia3Dart] Analysis error: $e');
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
    _model?.close();
    _model = null;
    _stateNotifier.value = EngineState.disposed;
  }

  /// The last [historySlots] positions of the game, current one last.
  ///
  /// Derived per call rather than accumulated in a field: engine-side state
  /// both skipped every other ply and leaked across games.
  List<String> _historyFor(String positionCommand) =>
      fenHistoryFromPositionCommand(positionCommand, limit: historySlots);

  /// Split into the prior positions plus the current one, the shape
  /// [resolveHistory] expects.
  HistoryInput _historyInput(List<String> history) => HistoryInput(
        fen: history.last,
        priorFens:
            history.length > 1 ? history.sublist(0, history.length - 1) : null,
      );
}
