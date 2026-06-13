// Maia3 engine for web — calls maia3-js via JavaScript interop.
// MIT licensed. Downloads ~21MB ONNX model on first use.

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

// JS bridge functions (defined in web/maia3_bridge.js)
@JS('maia3Load')
external JSPromise<JSAny?> _maia3Load(JSString variant, JSFunction? onProgress);

@JS('maia3Predict')
external JSPromise<JSAny?> _maia3Predict(
    JSString fen, JSNumber selfElo, JSAny? oppoElo, JSAny? priorFens);

@JS('maia3Close')
external JSPromise<JSAny?> _maia3Close();

// Typed result from maia3Predict
extension type Maia3Result._(JSObject _) implements JSObject {
  external JSString get bestMove;
  external JSNumber get winProbability;
}

/// Maia3 engine for web. Same class name as native stub for conditional import.
class Maia3Engine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final int playerElo;
  final String variant;
  bool _loaded = false;
  final List<String> _fenHistory = [];

  Maia3Engine({this.playerElo = 1500, this.variant = '5m'});

  @override
  String get name => 'Maia3 ($variant)';
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
      debugPrint('[Maia3Web] Loading variant=$variant...');
      await _maia3Load(variant.toJS, null).toDart;
      _loaded = true;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Maia3Web] Ready');
    } catch (e) {
      debugPrint('[Maia3Web] Failed: $e');
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
    if (!_loaded) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    final fen = _extractFen(positionCommand);
    final elo = skillLevel != null ? 800 + (skillLevel * 60) : playerElo;

    try {
      final jsResult = await _maia3Predict(
        fen.toJS, elo.toJS, null, null,
      ).toDart;

      final result = jsResult as Maia3Result;
      final move = result.bestMove.toDart;

      _fenHistory.add(fen);
      if (_fenHistory.length > 8) _fenHistory.removeAt(0);

      debugPrint('[Maia3Web] $move (elo=$elo)');
      _stateNotifier.value = EngineState.ready;
      return move;
    } catch (e) {
      debugPrint('[Maia3Web] Predict failed: $e');
      _stateNotifier.value = EngineState.ready;
      rethrow;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) async* {
    if (!_loaded) return;
    _stateNotifier.value = EngineState.thinking;
    final fen = _extractFen(positionCommand);

    try {
      final jsResult = await _maia3Predict(
        fen.toJS, playerElo.toJS, null, null,
      ).toDart;

      final result = jsResult as Maia3Result;
      final wp = result.winProbability.toDartDouble;
      final score = (wp - 0.5) * 10.0;

      yield EvalInfo(
        score: score,
        depth: 1,
        bestMove: result.bestMove.toDart,
      );
    } catch (e) {
      debugPrint('[Maia3Web] Analysis failed: $e');
    }
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void stop() => _stateNotifier.value = EngineState.ready;

  @override
  void dispose() {
    _maia3Close().toDart.catchError((_) {});
    _loaded = false;
    _fenHistory.clear();
    _stateNotifier.value = EngineState.disposed;
  }

  String _extractFen(String cmd) {
    final parts = cmd.split(' ');
    if (parts.length >= 2 && parts[1] == 'fen') {
      final mi = parts.indexOf('moves');
      return mi > 0 ? parts.sublist(2, mi).join(' ') : parts.sublist(2).join(' ');
    }
    return 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  }
}
