/// Fitting a search into the time it was given.
///
/// A search call that cannot be interrupted has to be sized before it starts,
/// and the engines here all do it the same way: turn the time remaining into a
/// node budget using a throughput learned from the last call. That arithmetic
/// was copied into four places — the native Frozenight driver, its browser
/// twin for play and again for analysis, and the Lynx adapter — and three of
/// those live in files `flutter test` cannot compile, so none of it was ever
/// checked. It is small, it is pure, and it decides whether a move lands
/// inside its budget, so it belongs somewhere a test can reach.
library;

/// Nodes to allow a search that has [remaining] time, at [nodesPerMs].
///
/// Floored at [floor] so a nearly-exhausted budget still produces a legal
/// move rather than an empty search, and capped well inside a 32-bit range
/// because the value crosses into WASM and FFI.
int nodeAllowance(Duration remaining, double nodesPerMs,
    {int floor = 4096, int ceiling = 2000000000}) {
  if (nodesPerMs <= 0 || remaining <= Duration.zero) return floor;
  final allowance = remaining.inMilliseconds * nodesPerMs;
  if (allowance.isNaN) return floor;
  if (allowance <= floor) return floor;
  if (allowance >= ceiling) return ceiling;
  return allowance.toInt();
}

/// Throughput after a search that visited [nodes] in [spentMs].
///
/// Half of the previous estimate and half of what just happened: a full board
/// and a bare endgame differ by a lot, so the recent rate matters more than
/// the average over a game. Samples too small to mean anything are ignored —
/// a search that returns in a millisecond says more about the clock's
/// resolution than about the engine.
///
/// The starting guess is averaged in like any other value rather than being
/// replaced by the first real measurement, so it takes about three searches to
/// converge from a deliberately low guess. Replacing it outright would
/// converge at once; it would also be a behaviour change dressed up as an
/// extraction, so it is not done here.
double updatedRate(double current, int nodes, int spentMs,
    {int minNodes = 4096}) {
  if (nodes < minNodes || spentMs <= 0) return current;
  return 0.5 * current + 0.5 * (nodes / spentMs);
}

/// Whether enough of [budget] is left to be worth another iteration.
///
/// An eighth: below that the iteration cannot do anything useful and its
/// result is discarded anyway when the clock runs out.
bool worthStartingDepth(Duration remaining, Duration budget) =>
    remaining > budget ~/ 8;

/// The budget to ask an engine for, given [overheadMs] spent outside its
/// search on every move.
///
/// Never less than half: a larger overhead reading than that means the clock
/// started somewhere it should not have, and following it would starve the
/// search rather than pace it.
Duration discountedBudget(Duration budget, int overheadMs) {
  final asked = budget.inMilliseconds - overheadMs;
  final floor = budget.inMilliseconds ~/ 2;
  return Duration(milliseconds: asked < floor ? floor : asked);
}
