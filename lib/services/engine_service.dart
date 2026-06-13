import 'dart:async';
import 'package:flutter/foundation.dart';
import '../engines/chess_engine.dart';

/// Events emitted by the engine service.
sealed class EngineEvent {}

class EvalUpdateEvent extends EngineEvent {
  final double eval;
  final int depth;
  final String bestMove;
  EvalUpdateEvent(
      {required this.eval, required this.depth, required this.bestMove});
}

class BestMoveEvent extends EngineEvent {
  final String move;
  BestMoveEvent(this.move);
}

class StateChangeEvent extends EngineEvent {
  final EngineState state;
  StateChangeEvent(this.state);
}

class EngineErrorEvent extends EngineEvent {
  final String message;
  EngineErrorEvent(this.message);
}

/// High-level service managing a [ChessEngine] instance.
///
/// Provides a clean [events] stream and handles engine lifecycle,
/// state change notifications, and error handling.
class EngineService {
  ChessEngine _engine;
  final _eventController = StreamController<EngineEvent>.broadcast();
  StreamSubscription<EvalInfo>? _analysisSubscription;
  VoidCallback? _stateListener;

  Stream<EngineEvent> get events => _eventController.stream;
  EngineState get state => _engine.state;
  ChessEngine get engine => _engine;
  String get engineName => _engine.name;
  String get engineLicense => _engine.license;
  int get estimatedElo => _engine.estimatedElo;

  EngineService(this._engine);

  /// Initialize the engine and start listening for state changes.
  Future<void> initialize() async {
    _stateListener = () {
      _eventController.add(StateChangeEvent(_engine.state));
    };
    _engine.stateNotifier.addListener(_stateListener!);

    try {
      await _engine.initialize();
    } catch (e) {
      _eventController.add(EngineErrorEvent('Init failed: $e'));
    }
  }

  /// Switch to a different engine. Disposes the current one.
  Future<void> switchEngine(ChessEngine newEngine) async {
    _analysisSubscription?.cancel();
    if (_stateListener != null) {
      _engine.stateNotifier.removeListener(_stateListener!);
    }
    _engine.dispose();

    _engine = newEngine;
    _eventController.add(StateChangeEvent(EngineState.initializing));
    await initialize();
  }

  /// Request the best move for a position.
  Future<void> requestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    try {
      final move = await _engine.bestMove(
        positionCommand,
        depth: depth,
        moveTime: moveTime,
        skillLevel: skillLevel,
      );
      _eventController.add(BestMoveEvent(move));
    } catch (e) {
      _eventController.add(EngineErrorEvent('Move request failed: $e'));
    }
  }

  /// Start analysis, streaming eval updates.
  Future<void> requestAnalysis(
    String positionCommand, {
    int? depth,
  }) async {
    _analysisSubscription?.cancel();

    try {
      _analysisSubscription =
          _engine.analyze(positionCommand, depth: depth).listen(
        (info) {
          _eventController.add(EvalUpdateEvent(
            eval: info.score,
            depth: info.depth,
            bestMove: info.bestMove ?? '',
          ));
        },
        onError: (e) {
          _eventController.add(EngineErrorEvent('Analysis error: $e'));
        },
      );
    } catch (e) {
      _eventController.add(EngineErrorEvent('Analysis failed: $e'));
    }
  }

  /// Stop the current engine search/analysis.
  void stop() {
    _analysisSubscription?.cancel();
    _engine.stop();
  }

  /// Dispose all resources.
  void dispose() {
    _analysisSubscription?.cancel();
    if (_stateListener != null) {
      _engine.stateNotifier.removeListener(_stateListener!);
    }
    _engine.dispose();
    _eventController.close();
  }
}
