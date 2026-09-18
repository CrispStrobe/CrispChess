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

  /// Builds a replacement when the current engine's process dies.
  ///
  /// Optional: without it a death is reported and play stops until the user
  /// picks another engine, which is what used to happen to every crash.
  final ChessEngine Function()? rebuildEngine;

  /// Restarts already spent. A process that dies once may have hit something
  /// transient; one that dies repeatedly is broken, and restarting it on every
  /// move turns one bad engine into an unusable app.
  int _restarts = 0;
  static const int _maxRestarts = 3;

  EngineService(this._engine, {this.rebuildEngine});

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
    Duration? budget;
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
      budget = moveTime ??
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
    } on EngineProcessDiedException catch (e) {
      // The engine is gone, not slow. Before these two could be told apart
      // there was nothing safe to do about it; now there is, and leaving a
      // dead process in place makes every later move fail the same way until
      // someone notices and switches engines by hand.
      final move = await _restartAndRetry(
          positionCommand, depth, budget, skillLevel, e);
      if (move != null) {
        _eventController.add(BestMoveEvent(move));
      }
    } catch (e) {
      _eventController.add(EngineErrorEvent('Move request failed: $e'));
    }
  }

  /// Replace a dead engine and ask again, once.
  ///
  /// Returns the move, or null when it could not be recovered — in which case
  /// the failure has already been reported and says what died.
  Future<String?> _restartAndRetry(
    String positionCommand,
    int? depth,
    Duration? budget,
    int? skillLevel,
    EngineProcessDiedException death,
  ) async {
    final rebuild = rebuildEngine;
    if (rebuild == null || _restarts >= _maxRestarts) {
      _eventController.add(EngineErrorEvent('$death'));
      return null;
    }
    _restarts++;
    _eventController.add(EngineErrorEvent('$death — restarting it'));

    try {
      _analysisSubscription?.cancel();
      if (_stateListener != null) {
        _engine.stateNotifier.removeListener(_stateListener!);
      }
      _engine.dispose();
      _engine = rebuild();
      await initialize();
      return await _engine.bestMove(
        positionCommand,
        depth: depth,
        moveTime: budget,
        skillLevel: skillLevel,
      );
    } catch (e) {
      _eventController.add(EngineErrorEvent('Restart failed: $e'));
      return null;
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
