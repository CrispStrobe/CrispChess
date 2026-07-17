import 'dart:async';
import 'package:flutter/foundation.dart';
import '../chess/opening_book.dart';
import '../engines/chess_engine.dart';
import '../engines/uci_position.dart';

/// Events emitted by the engine service.
sealed class EngineEvent {}

class EvalUpdateEvent extends EngineEvent {
  final double eval;
  final int depth;
  final String bestMove;
  final String? pv;       // full principal variation (space-separated UCI)
  final int pvIndex;      // Multi-PV line number (1 = best)
  EvalUpdateEvent({
    required this.eval,
    required this.depth,
    required this.bestMove,
    this.pv,
    this.pvIndex = 1,
  });
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
  bool useOpeningBook = true;

  Stream<EngineEvent> get events => _eventController.stream;
  EngineState get state => _engine.state;
  ChessEngine get engine => _engine;
  String get engineName => _engine.name;
  String get engineVersion => _engine.version;
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
  ///
  /// Checks the opening book first (if enabled). Falls back to the engine.
  Future<void> requestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    try {
      // Try opening book first
      if (useOpeningBook && depth == null) {
        final fen = fenFromPositionCommand(positionCommand);
        final bookMove = OpeningBook.pickMove(fen);
        if (bookMove != null) {
          debugPrint('[EngineService] Book move: $bookMove');
          _eventController.add(BestMoveEvent(bookMove));
          return;
        }
      }

      // Drive normal play by time, not a fixed depth. Callers that ask for an
      // explicit depth (hints/analysis) keep that behaviour.
      final budget = moveTime ??
          (depth == null && skillLevel != null
              ? thinkTimeForLevel(skillLevel)
              : null);

      final move = await _engine.bestMove(
        positionCommand,
        depth: depth,
        moveTime: budget,
        skillLevel: skillLevel,
      );
      _eventController.add(BestMoveEvent(move));
    } catch (e) {
      _eventController.add(EngineErrorEvent('Move request failed: $e'));
    }
  }

  /// Start analysis, streaming eval updates.
  ///
  /// Pass [infinite] = true for open-ended analysis that runs until
  /// [stop()] is called.
  Future<void> requestAnalysis(
    String positionCommand, {
    int? depth,
    bool infinite = false,
  }) async {
    _analysisSubscription?.cancel();

    try {
      _analysisSubscription =
          _engine.analyze(positionCommand, depth: depth, infinite: infinite).listen(
        (info) {
          _eventController.add(EvalUpdateEvent(
            eval: info.score,
            depth: info.depth,
            bestMove: info.bestMove ?? '',
            pv: info.pv,
            pvIndex: info.pvIndex,
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
