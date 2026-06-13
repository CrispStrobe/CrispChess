/// Maia3 Dart engine — pure Dart port of maia3-js.
///
/// All tokenization, move vocabulary, and sampling logic is in Dart.
/// Only ONNX inference is platform-specific (native FFI / web JS interop).
///
/// This is the native/stub version. On web, the conditional import
/// in engine_factory.dart resolves to maia3_dart_web_engine.dart instead.
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
import 'maia3_dart/onnx_model_native.dart';
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
  final List<String> _fenHistory = [];

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
      _model = Maia3NativeOnnxModel(variant: variant);
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
      final fen = _extractFen(positionCommand);
      final selfElo = skillLevel != null
          ? (800 + (skillLevel * 60)).clamp(0, 5000)
          : playerElo.clamp(0, 5000);
      final oppoElo = selfElo; // Assume equal opponent

      // Build history tokens
      final historyInput = HistoryInput(
        fen: fen,
        priorFens: _fenHistory.length > 1 ? _fenHistory : null,
      );
      final boards = resolveHistory(historyInput);
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

      // Track history
      _fenHistory.add(fen);
      if (_fenHistory.length > 8) _fenHistory.removeAt(0);

      _stateNotifier.value = EngineState.ready;
      return bestUci;
    } catch (e) {
      debugPrint('[Maia3Dart] Prediction failed: $e');
      _stateNotifier.value = EngineState.ready;
      rethrow;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) async* {
    // Maia3 provides WDL, not depth-based eval
    if (_model == null) return;
    _stateNotifier.value = EngineState.thinking;

    try {
      final fen = _extractFen(positionCommand);
      final selfElo = playerElo.clamp(0, 5000);
      final boards = resolveHistory(HistoryInput(fen: fen));
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
  void dispose() {
    _model?.close();
    _model = null;
    _fenHistory.clear();
    _stateNotifier.value = EngineState.disposed;
  }

  String _extractFen(String cmd) => fenFromPositionCommand(cmd);
}
