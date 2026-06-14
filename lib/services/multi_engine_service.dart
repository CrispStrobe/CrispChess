import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback;
import '../engines/chess_engine.dart';

/// Events from a specific engine in multi-engine analysis.
sealed class MultiEngineEvent {}

class MultiEvalUpdate extends MultiEngineEvent {
  final int engineIndex;
  final String engineName;
  final double eval;
  final int depth;
  final String bestMove;
  final String? pv;

  MultiEvalUpdate({
    required this.engineIndex,
    required this.engineName,
    required this.eval,
    required this.depth,
    required this.bestMove,
    this.pv,
  });
}

class MultiEngineStateChange extends MultiEngineEvent {
  final int engineIndex;
  final String engineName;
  final EngineState state;

  MultiEngineStateChange({
    required this.engineIndex,
    required this.engineName,
    required this.state,
  });
}

/// Snapshot of one engine's latest analysis result.
class EngineAnalysisResult {
  final String engineName;
  final double eval;
  final int depth;
  final String bestMove;
  final String? pv;
  final EngineState state;

  EngineAnalysisResult({
    required this.engineName,
    this.eval = 0,
    this.depth = 0,
    this.bestMove = '',
    this.pv,
    this.state = EngineState.idle,
  });

  EngineAnalysisResult copyWith({
    double? eval,
    int? depth,
    String? bestMove,
    String? pv,
    EngineState? state,
  }) {
    return EngineAnalysisResult(
      engineName: engineName,
      eval: eval ?? this.eval,
      depth: depth ?? this.depth,
      bestMove: bestMove ?? this.bestMove,
      pv: pv ?? this.pv,
      state: state ?? this.state,
    );
  }
}

/// Manages multiple chess engines analyzing the same position simultaneously.
class MultiEngineService {
  final List<ChessEngine> _engines = [];
  final List<StreamSubscription<EvalInfo>?> _subscriptions = [];
  final List<VoidCallback> _stateListeners = [];
  final _eventController = StreamController<MultiEngineEvent>.broadcast();

  /// Latest results from each engine.
  final List<EngineAnalysisResult> results = [];

  Stream<MultiEngineEvent> get events => _eventController.stream;
  int get engineCount => _engines.length;
  bool get isEmpty => _engines.isEmpty;

  /// Add an engine to the analysis pool.
  Future<void> addEngine(ChessEngine engine) async {
    final index = _engines.length;
    _engines.add(engine);
    _subscriptions.add(null);
    results.add(EngineAnalysisResult(
      engineName: engine.name,
      state: engine.state,
    ));

    void listener() {
      if (index < results.length) {
        results[index] = results[index].copyWith(state: engine.state);
        _eventController.add(MultiEngineStateChange(
          engineIndex: index,
          engineName: engine.name,
          state: engine.state,
        ));
      }
    }
    engine.stateNotifier.addListener(listener);
    _stateListeners.add(listener);

    if (engine.state == EngineState.idle) {
      await engine.initialize();
    }
  }

  /// Start all engines analyzing the same position.
  void analyzeAll(String positionCommand, {int? depth, bool infinite = false}) {
    for (int i = 0; i < _engines.length; i++) {
      _subscriptions[i]?.cancel();

      final engine = _engines[i];
      if (engine.state != EngineState.ready &&
          engine.state != EngineState.thinking) continue;

      final idx = i;
      _subscriptions[i] = engine
          .analyze(positionCommand, depth: depth, infinite: infinite)
          .listen((info) {
        if (idx < results.length) {
          results[idx] = results[idx].copyWith(
            eval: info.score,
            depth: info.depth,
            bestMove: info.bestMove,
            pv: info.pv,
          );
          _eventController.add(MultiEvalUpdate(
            engineIndex: idx,
            engineName: engine.name,
            eval: info.score,
            depth: info.depth,
            bestMove: info.bestMove ?? '',
            pv: info.pv,
          ));
        }
      });
    }
  }

  /// Stop all engines.
  void stopAll() {
    for (int i = 0; i < _engines.length; i++) {
      _subscriptions[i]?.cancel();
      _engines[i].stop();
    }
  }

  /// Remove an engine by index.
  void removeEngine(int index) {
    if (index < 0 || index >= _engines.length) return;
    _subscriptions[index]?.cancel();
    _engines[index].stateNotifier.removeListener(_stateListeners[index]);
    _engines[index].dispose();
    _engines.removeAt(index);
    _subscriptions.removeAt(index);
    _stateListeners.removeAt(index);
    results.removeAt(index);
  }

  /// Dispose all engines and close the stream.
  void dispose() {
    for (int i = 0; i < _engines.length; i++) {
      _subscriptions[i]?.cancel();
      _engines[i].stateNotifier.removeListener(_stateListeners[i]);
      _engines[i].dispose();
    }
    _engines.clear();
    _subscriptions.clear();
    _stateListeners.clear();
    results.clear();
    _eventController.close();
  }
}
