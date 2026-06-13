// Maia3 engine for web — calls maia3-js via JavaScript interop.
// Loads the 5M model (~21MB ONNX) from CDN on first use.
// MIT licensed. No GPL code anywhere.

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

@JS('maia3Load')
external JSPromise<JSAny?> _maia3Load(JSString variant, JSFunction? onProgress);

@JS('maia3Predict')
external JSPromise<JSObject> _maia3Predict(
    JSString fen, JSNumber selfElo, JSNumber? oppoElo, JSArray<JSString>? priorFens);

@JS('maia3Close')
external JSPromise<JSAny?> _maia3Close();

/// Maia3 engine running on web via maia3-js + ONNX Runtime WASM.
///
/// Human-like chess play conditioned on ELO rating.
/// Downloads 21MB model on first use (cached in browser Cache Storage).
class Maia3WebEngine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final int playerElo;
  final String variant;
  bool _loaded = false;

  final List<String> _fenHistory = [];

  Maia3WebEngine({this.playerElo = 1500, this.variant = '5m'});

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
      debugPrint('[Maia3Web] Loading model variant=$variant...');
      await _maia3Load(variant.toJS, null).toDart;
      _loaded = true;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Maia3Web] Model loaded');
    } catch (e) {
      debugPrint('[Maia3Web] Load failed: $e');
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
      final priorFensJs = _fenHistory.isNotEmpty
          ? _fenHistory.map((f) => f.toJS).toList().toJS
          : null;

      final result = await _maia3Predict(
        fen.toJS,
        elo.toJS,
        null,
        priorFensJs,
      ).toDart;

      final bestMove = (result as JSObject).getProperty('bestMove'.toJS);
      final move = (bestMove as JSString).toDart;

      _fenHistory.add(fen);
      if (_fenHistory.length > 8) _fenHistory.removeAt(0);

      debugPrint('[Maia3Web] Predicted: $move (elo=$elo)');
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
      final result = await _maia3Predict(
        fen.toJS, playerElo.toJS, null, null,
      ).toDart;

      final winProb = (result as JSObject)
          .getProperty('winProbability'.toJS) as JSNumber;
      final bestMove = (result.getProperty('bestMove'.toJS) as JSString).toDart;

      // Convert win probability to centipawn-like score
      final wp = winProb.toDartDouble;
      final score = wp > 0.5
          ? (wp - 0.5) * 10.0
          : -(0.5 - wp) * 10.0;

      yield EvalInfo(
        score: score,
        depth: 1,
        bestMove: bestMove,
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

  String _extractFen(String positionCommand) {
    final parts = positionCommand.split(' ');
    if (parts.length >= 2 && parts[1] == 'fen') {
      final mi = parts.indexOf('moves');
      return mi > 0 ? parts.sublist(2, mi).join(' ') : parts.sublist(2).join(' ');
    }
    return 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  }
}
