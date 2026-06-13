// Maia3 engine for web — calls maia3-js via JavaScript interop.
// MIT licensed. Downloads ONNX model on first use.

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'uci_position.dart';

// JS bridge functions (defined in web/maia3_bridge.js)
@JS('maia3Load')
external JSPromise<JSAny?> _jsLoad(JSString variant, JSAny? onProgress);

@JS('maia3Close')
external JSPromise<JSAny?> _jsClose();

// Predict returns a string (bestMove)
@JS('maia3PredictMove')
external JSPromise<JSString> _jsPredictMove(JSString fen, JSNumber selfElo);

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
      await _jsLoad(variant.toJS, null).toDart;
      _loaded = true;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Maia3] Ready (variant: $variant)');
    } catch (e) {
      debugPrint('[Maia3] Failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  @override
  Future<String> bestMove(String positionCommand, {
    int? depth, Duration? moveTime, int? skillLevel,
  }) async {
    if (!_loaded) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    final fen = _extractFen(positionCommand);
    final elo = skillLevel != null ? 800 + (skillLevel * 60) : playerElo;

    try {
      final move = (await _jsPredictMove(fen.toJS, elo.toJS).toDart).toDart;
      _stateNotifier.value = EngineState.ready;
      return move;
    } catch (e) {
      _stateNotifier.value = EngineState.ready;
      rethrow;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) async* {
    // Maia3 doesn't do depth-based analysis — single prediction only
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void stop() => _stateNotifier.value = EngineState.ready;

  @override
  void dispose() {
    _jsClose().toDart.catchError((_) {});
    _loaded = false;
    _stateNotifier.value = EngineState.disposed;
  }

  String _extractFen(String cmd) => fenFromPositionCommand(cmd);
}
