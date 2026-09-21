/// Holding an engine that might die.
///
/// An engine kept in a field and reused is the normal arrangement — starting
/// one costs a process, a download or a model load — but it has a failure
/// mode that has now appeared twice here. A process that dies leaves its
/// engine in [EngineState.error], which is neither `idle` nor `disposed`, so
/// the usual `??=` keeps the dead instance and the usual "initialise if idle"
/// guard never fires again. Every later request fails, identically, forever.
///
/// The hint engine had exactly that: one crash and every hint after it
/// reported "Hint failed", advice that could not have helped.
library;

import 'chess_engine.dart';

/// Whether an engine in this state can still be asked for anything.
///
/// `disposed` is included because a slot outliving its engine is the same
/// problem wearing a different state.
bool engineNeedsRebuild(EngineState state) =>
    state == EngineState.error || state == EngineState.disposed;

/// An engine that is built on demand and replaced when it becomes unusable.
class EngineSlot {
  EngineSlot(this._build);

  final ChessEngine Function() _build;
  ChessEngine? _current;

  /// How many times the engine has been replaced, for callers that want to
  /// stop after a while rather than restart something permanently broken.
  int rebuilds = 0;

  /// The engine held right now, without building or replacing anything.
  ChessEngine? get current => _current;

  /// A usable engine, initialised and ready to be asked.
  Future<ChessEngine> get() async {
    final cached = _current;
    if (cached != null && engineNeedsRebuild(cached.state)) {
      _disposeQuietly(cached);
      _current = null;
      rebuilds++;
    }

    final engine = _current ??= _build();
    if (engine.state == EngineState.idle) {
      await engine.initialize();
    }
    return engine;
  }

  void dispose() {
    final cached = _current;
    if (cached != null) _disposeQuietly(cached);
    _current = null;
  }

  /// Disposing something already gone is not an error worth propagating: the
  /// point is only to stop holding it.
  void _disposeQuietly(ChessEngine engine) {
    try {
      engine.dispose();
    } catch (_) {}
  }
}
