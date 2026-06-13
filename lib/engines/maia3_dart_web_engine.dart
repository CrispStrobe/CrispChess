/// Maia3 Dart engine — web version.
///
/// Same pure Dart logic as native, but uses onnxruntime-web via JS bridge
/// for ONNX inference (maia3_onnx_bridge.js).
///
/// License: MIT.

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:chess/chess.dart' as chess_lib;

import 'chess_engine.dart';
import 'maia3_dart/encoding.dart';
import 'maia3_dart/history.dart';
import 'maia3_dart/moves.dart' as moves;
import 'maia3_dart/onnx_model.dart';
import 'maia3_dart/onnx_model_web.dart';
import 'maia3_dart/utils.dart';
import 'maia3_dart/variants.dart';

/// Maia3 Dart engine for web — same logic, web ONNX backend.
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
  String get name => 'Maia3 Dart ($variantId)';
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
      _model = Maia3WebOnnxModel(variant: variant);
      await _model!.load();
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Maia3Dart/Web] Ready (${variant.displayName})');
    } catch (e) {
      debugPrint('[Maia3Dart/Web] Init failed: $e');
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
      final oppoElo = selfElo;

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

      _fenHistory.add(fen);
      if (_fenHistory.length > 8) _fenHistory.removeAt(0);

      _stateNotifier.value = EngineState.ready;
      return bestUci;
    } catch (e) {
      debugPrint('[Maia3Dart/Web] Prediction failed: $e');
      _stateNotifier.value = EngineState.ready;
      rethrow;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) async* {
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
      final score = (winProb - 0.5) * 10.0;

      yield EvalInfo(score: score, depth: 1, bestMove: null);
    } catch (e) {
      debugPrint('[Maia3Dart/Web] Analysis error: $e');
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

  String _extractFen(String cmd) {
    final parts = cmd.split(' ');
    if (parts.length >= 2 && parts[1] == 'fen') {
      final mi = parts.indexOf('moves');
      return mi > 0
          ? parts.sublist(2, mi).join(' ')
          : parts.sublist(2).join(' ');
    }
    return 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  }
}
