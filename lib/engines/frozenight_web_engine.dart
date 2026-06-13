// Frozenight WASM engine for web.
// MIT/Apache-2.0 licensed. ~3226 ELO (CCRL 40/15).
// Compiled from Rust to WASM via wasm-bindgen.
// Single-threaded (no Web Worker needed — runs synchronously per call).

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

@JS('frozenightLoad')
external JSPromise<JSAny?> _frozenightLoad();

@JS('frozenightSetPosition')
external void _frozenightSetPosition(JSString fen, JSString moves);

@JS('frozenightSearch')
external JSString _frozenightSearch(JSNumber depth);

@JS('frozenightGetEval')
external JSNumber _frozenightGetEval();

@JS('frozenightDispose')
external void _frozenightDispose();

@JS('frozenightIsLoaded')
external JSBoolean _frozenightIsLoaded();

/// Frozenight NNUE engine running as WASM in the browser.
///
/// ~3226 ELO (CCRL). MIT/Apache-2.0 licensed.
/// Single-threaded — search runs synchronously per depth.
/// Uses incremental deepening with UI yields between depths.
class FrozenightEngine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  bool _loaded = false;

  @override
  String get name => 'Frozenight';
  @override
  String get version => '6.0 (WASM)';
  @override
  String get license => 'MIT/Apache-2.0';
  @override
  int get estimatedElo => 3226;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  static bool get isAvailable => kIsWeb;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      debugPrint('[FrozenightWASM] Loading...');
      await _frozenightLoad().toDart;
      _loaded = true;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[FrozenightWASM] Ready (~3226 ELO)');
    } catch (e) {
      debugPrint('[FrozenightWASM] Not available: $e');
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

    _applyPosition(positionCommand);

    final searchDepth = depth ?? (2 + (skillLevel ?? 10) * 12 ~/ 20).clamp(2, 14);
    final webDepth = searchDepth.clamp(1, 10); // Cap for responsiveness

    // Yield to UI before blocking search
    await Future.delayed(Duration.zero);

    final sw = Stopwatch()..start();
    String? bestMove;

    // Incremental deepening with UI yields
    for (int d = 1; d <= webDepth; d++) {
      await Future.delayed(Duration.zero);
      final move = _frozenightSearch(d.toJS).toDart;
      if (move.isNotEmpty && move != '0000') bestMove = move;
      if (sw.elapsedMilliseconds > 2000) break; // Time limit
    }

    debugPrint('[FrozenightWASM] $bestMove depth=$webDepth ${sw.elapsedMilliseconds}ms');
    _stateNotifier.value = EngineState.ready;

    if (bestMove == null || bestMove == '0000') throw StateError('No move');
    return bestMove;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) async* {
    if (!_loaded) return;
    _stateNotifier.value = EngineState.thinking;
    _applyPosition(positionCommand);

    for (int d = 1; d <= (depth ?? 15); d++) {
      await Future.delayed(Duration.zero);
      final move = _frozenightSearch(d.toJS).toDart;
      final eval = _frozenightGetEval().toDartInt;

      yield EvalInfo(
        score: eval / 100.0,
        depth: d,
        bestMove: move.isNotEmpty && move != '0000' ? move : null,
      );
    }

    _stateNotifier.value = EngineState.ready;
  }

  @override
  void stop() => _stateNotifier.value = EngineState.ready;

  @override
  void dispose() {
    if (_loaded) _frozenightDispose();
    _loaded = false;
    _stateNotifier.value = EngineState.disposed;
  }

  void _applyPosition(String positionCommand) {
    debugPrint('[FrozenightWASM] Position: $positionCommand');
    final parts = positionCommand.split(' ');
    String fen = 'startpos';
    String moves = '';

    if (parts.length >= 2 && parts[1] == 'fen') {
      final mi = parts.indexOf('moves');
      fen = mi > 0 ? parts.sublist(2, mi).join(' ') : parts.sublist(2).join(' ');
      if (mi > 0) moves = parts.sublist(mi + 1).join(' ');
    } else {
      final mi = parts.indexOf('moves');
      if (mi > 0) moves = parts.sublist(mi + 1).join(' ');
    }

    _frozenightSetPosition(fen.toJS, moves.toJS);
  }
}
