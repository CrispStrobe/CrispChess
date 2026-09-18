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

@JS('frozenightSearchBounded')
external JSString _frozenightSearchBounded(JSNumber depth, JSNumber maxNodes);

@JS('frozenightGetEval')
external JSNumber _frozenightGetEval();

@JS('frozenightDispose')
external void _frozenightDispose();

/// Frozenight NNUE engine running as WASM in the browser.
///
/// ~3226 ELO (CCRL). MIT/Apache-2.0 licensed.
/// Single-threaded — search runs synchronously per depth.
/// Uses incremental deepening with UI yields between depths.
class FrozenightEngine implements ChessEngine {
  /// Nodes per millisecond, measured as the search runs. Only the initial
  /// value is a guess, and it is deliberately low: guessing high on the first
  /// search of a session is the one case that cannot be corrected afterwards.
  double _nodesPerMs = 50;

  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  bool _loaded = false;
  bool _stopped = false;

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

  // The WASM search runs synchronously between event-loop yields, so a
  // background ponder search would stall the UI for as long as it runs.
  @override
  bool get canPonder => false;

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

    // The depth ceiling is the difficulty knob, and at full strength it should
    // not be one: the clock should end the search. The extra cap at 10 was
    // there for responsiveness, which is now the node bound's job — a depth
    // that does not fit is cut short instead of running to completion.
    final searchDepth = depth ??
        (skillLevel != null && skillLevel >= 20
            ? 64
            : (2 + (skillLevel ?? 10) * 12 ~/ 20).clamp(2, 14));
    final webDepth = searchDepth.clamp(1, 64);
    final budget = moveTime ??
        (depth != null ? kFixedDepthTimeCap : thinkTimeForLevel(skillLevel ?? 10));

    // Yield to UI before blocking search
    await Future.delayed(Duration.zero);

    final sw = Stopwatch()..start();
    String? bestMove;
    var reached = 0;

    // Iterative deepening, bounded by a node count rather than by guessing
    // which depth will fit.
    //
    // A search call runs to completion and cannot be interrupted, so deciding
    // before each depth whether it will fit is a guess — and in an endgame it
    // is a bad one: iterations stay cheap for many plies, so the guard never
    // trips, and then one of them explodes. The tournament caught exactly that
    // twice, both past ply 100, each time sitting for the full 60-second hang
    // cutoff. Handing the engine a node budget it checks on every node turns
    // a hang into an early return.
    for (int d = 1; d <= webDepth; d++) {
      final remaining = budget - sw.elapsed;
      if (d > 1 && remaining <= budget ~/ 8) break;
      await Future.delayed(Duration.zero);

      final before = sw.elapsed;
      final allowance = (remaining.inMilliseconds * _nodesPerMs)
          .clamp(4096, 2000000000)
          .toDouble();
      var answer = _frozenightSearchBounded(d.toJS, allowance.toJS).toDart;

      String move;
      if (answer.isEmpty) {
        // A bundle older than `search_bounded`; fall back to the unbounded
        // call and the guess that goes with it.
        if (d > 1 && !hasTimeForNextDepth(before, budget)) break;
        move = _frozenightSearch(d.toJS).toDart;
      } else {
        final space = answer.indexOf(' ');
        move = space < 0 ? answer : answer.substring(0, space);
        final nodes =
            space < 0 ? 0 : int.tryParse(answer.substring(space + 1)) ?? 0;
        final spent = (sw.elapsed - before).inMilliseconds;
        if (nodes > 4096 && spent > 0) {
          // Follow the recent rate: throughput differs a lot between a full
          // board and a bare endgame.
          _nodesPerMs = 0.5 * _nodesPerMs + 0.5 * (nodes / spent);
        }
      }

      if (move.isNotEmpty && move != '0000') {
        bestMove = move;
        reached = d;
      }
    }

    debugPrint('[FrozenightWASM] $bestMove depth=$reached/$webDepth '
        '${sw.elapsedMilliseconds}ms (budget ${budget.inMilliseconds}ms)');
    _stateNotifier.value = EngineState.ready;

    if (bestMove == null || bestMove == '0000') throw StateError('No move');
    return bestMove;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {
    if (!_loaded) return;
    _stateNotifier.value = EngineState.thinking;
    _stopped = false;
    _applyPosition(positionCommand);

    // Bounded even when [infinite]: each depth is one uninterruptible WASM
    // call, so the only way to stay responsive is to stop starting new ones.
    final budget = infinite ? const Duration(seconds: 10) : kFixedDepthTimeCap;
    final sw = Stopwatch()..start();

    for (int d = 1; d <= (depth ?? 15); d++) {
      if (_stopped) break;
      if (d > 1 && !hasTimeForNextDepth(sw.elapsed, budget)) break;
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
  void stop() {
    _stopped = true;
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void setOption(String name, String value) {
    // Frozenight WASM engine doesn't support runtime option changes
    // Options would need to be implemented in the WASM module
  }

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
