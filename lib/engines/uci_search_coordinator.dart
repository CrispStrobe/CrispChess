import 'dart:async';

/// Serialises searches on a single UCI engine connection.
///
/// UCI has exactly one search in flight at a time: after `go` the engine owns
/// the connection until it prints `bestmove`. The app breaks that rule in
/// normal play — it starts a background (ponder) analysis after every engine
/// move, then sends a new `position` + `go` as soon as the player moves. Two
/// things went wrong:
///
///  * the `bestmove` belonging to the *aborted* ponder search arrived first and
///    was handed back as the answer to the new request, so the engine "played"
///    a move computed for the previous position — usually illegal, which left
///    the UI stuck on "thinking" forever;
///  * the new `position` was parsed while the old search was still running, so
///    the engine could search the wrong tree.
///
/// Both get worse the longer the game runs, because a fixed-depth ponder search
/// takes longer every move — which is what read as "the engine dies after a few
/// turns".
///
/// This mixin makes the rule explicit: a new search always drains the previous
/// one first, and a `bestmove` only ever resolves the search that asked for it.
mixin UciSearchCoordinator {
  /// Write one UCI command to the engine. Implemented by each transport
  /// (process stdin, web worker `postMessage`, platform channel, ...).
  void sendUci(String command);

  /// Completes when the search in flight ends. Null when the engine is idle.
  Completer<void>? _running;

  /// Set when a caller is waiting for this search's `bestmove`.
  Completer<String?>? _awaited;

  /// True while a `go` is outstanding.
  bool get isSearching => _running != null;

  /// Stop the search in flight (if any) and wait for its `bestmove`.
  ///
  /// Returns immediately when the engine is idle. If the engine does not answer
  /// within [timeout] the search is dropped so it can never block the next one.
  Future<void> quiesceSearch(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final running = _running;
    if (running == null) return;
    sendUci('stop');
    await running.future.timeout(timeout, onTimeout: () => finishSearch(null));
  }

  /// Drain any previous search, then send [positionCommand] and [goCommand].
  ///
  /// With [awaitMove] the returned future carries that search's `bestmove` (or
  /// null if it was aborted or produced none). Without it the future completes
  /// as soon as the commands are sent — the caller only wants the `info` lines.
  Future<String?> startSearch(
    String positionCommand,
    String goCommand, {
    required bool awaitMove,
  }) async {
    await quiesceSearch();
    _running = Completer<void>();
    final waiter = awaitMove ? Completer<String?>() : null;
    _awaited = waiter;
    sendUci(positionCommand);
    sendUci(goCommand);
    return waiter?.future;
  }

  /// Feed every `bestmove` line here, with the move or null when the engine
  /// reported `(none)`.
  ///
  /// A `bestmove` that arrives with nothing outstanding is a leftover from an
  /// already-abandoned search and is discarded — never adopted as the answer to
  /// a later request.
  void finishSearch(String? move) {
    final waiter = _awaited;
    final running = _running;
    _awaited = null;
    _running = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(move);
    if (running != null && !running.isCompleted) running.complete();
  }

  /// Abort the search in flight without waiting for the engine to answer.
  /// Use when the connection is going away (dispose, process death).
  void abandonSearch() {
    sendUci('stop');
    finishSearch(null);
  }
}
