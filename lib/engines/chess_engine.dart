import 'package:flutter/foundation.dart';

/// State of a chess engine.
enum EngineState { idle, initializing, ready, thinking, error, disposed }

/// Evaluation information from engine analysis.
class EvalInfo {
  final double score; // in pawns, from white's perspective
  final int depth;
  final String? bestMove; // UCI format
  final String? pv; // principal variation (space-separated UCI moves)
  final int pvIndex; // Multi-PV line number (1-based, 1 = best line)

  const EvalInfo({
    required this.score,
    required this.depth,
    this.bestMove,
    this.pv,
    this.pvIndex = 1,
  });

  @override
  String toString() =>
      'EvalInfo(score: $score, depth: $depth, bestMove: $bestMove, pv#$pvIndex)';
}

/// Abstract interface for pluggable chess engines.
///
/// All engines must implement this interface. The app codes against
/// [ChessEngine], never against a specific engine implementation.
abstract class ChessEngine {
  /// Human-readable engine name.
  String get name;

  /// Engine version string.
  String get version;

  /// License identifier (e.g. 'MIT', 'GPL-3.0').
  String get license;

  /// Approximate ELO rating.
  int get estimatedElo;

  /// Current engine state.
  EngineState get state;

  /// Notifier for state changes.
  ValueNotifier<EngineState> get stateNotifier;

  /// Initialize the engine. Must be called before [bestMove] or [analyze].
  Future<void> initialize();

  /// Request the best move for a position.
  ///
  /// [positionCommand] is a UCI position string, e.g.
  /// `'position startpos moves e2e4 e7e5'`.
  ///
  /// Returns the best move in UCI format (e.g. `'d2d4'`).
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  });

  /// Stream evaluation updates for a position (analysis mode).
  ///
  /// Emits [EvalInfo] at each search depth until stopped or [depth] reached.
  /// Pass [infinite] = true for open-ended analysis (engine runs until
  /// [stop()] is called). When [infinite] is true, [depth] is ignored.
  Stream<EvalInfo> analyze(
    String positionCommand, {
    int? depth,
    bool infinite = false,
  });

  /// Abort the current search.
  void stop();

  /// Set a UCI option. No-op for engines that don't support UCI options.
  void setOption(String name, String value) {}

  /// Release all engine resources.
  void dispose();
}

/// Per-move think time for a 0-20 strength level.
///
/// Engines are driven by *time*, not a fixed depth. A fixed depth is what made
/// moves take 10-25s on a tablet (the built-in search) and made Stockfish grind
/// a full `go depth 15` in WASM even at low Skill Level — Skill Level caps
/// strength, not search time. Scales level 0 (~200ms, snappy) to level 20 (~2s).
Duration thinkTimeForLevel(int skillLevel) =>
    Duration(milliseconds: 200 + (skillLevel.clamp(0, 20) * 90));

/// Time cap for an explicit fixed-depth request (hints/analysis). Generous
/// enough not to weaken the answer, but still bounded so nothing can hang.
const Duration kFixedDepthTimeCap = Duration(seconds: 5);

/// Per-move think time when a real clock is running, derived from the engine's
/// own [remaining] time and the Fischer [incrementSeconds].
///
/// Replaces the flat per-level budget for clocked games. The flat budget both
/// *flags* the engine in bullet (a 2s cap x ~30 moves spends a 1-minute clock)
/// and *wastes* long clocks (the strongest bot would leave 29 of 30 minutes
/// unused). This instead:
///  - takes a fair slice of the clock (~1/30) plus most of the increment,
///  - never commits more than a quarter of the clock, or an absolute 30s (app
///    UX cap), to one move,
///  - keeps a safety margin so a search can never flag the clock — and because
///    the slice shrinks with the clock, it asymptotically never runs out,
///  - blends toward the flat per-level budget for weak levels, so a weak bot
///    stays fast (and weak) while the strongest uses the full slice.
Duration clockAwareThinkTime({
  required Duration remaining,
  required int incrementSeconds,
  required int skillLevel,
}) {
  final remMs = remaining.inMilliseconds;
  if (remMs <= 0) return const Duration(milliseconds: 50);

  var slice = remMs ~/ 30 + (incrementSeconds * 1000 * 7) ~/ 10;
  final quarter = remMs ~/ 4;
  if (slice > quarter) slice = quarter;
  if (slice > 30000) slice = 30000; // absolute per-move cap for app UX

  final safety = (remMs ~/ 10).clamp(200, 3000);
  final usable = remMs - safety;
  if (slice > usable) slice = usable > 50 ? usable : 50;
  if (slice < 50) slice = 50;

  // Weak levels play fast (near the flat per-level budget); strong levels use
  // the full slice. Linear blend by level.
  final levelMs = thinkTimeForLevel(skillLevel).inMilliseconds;
  final weakTarget = levelMs < slice ? levelMs : slice;
  final t = skillLevel.clamp(0, 20) / 20;
  var ms = (weakTarget + (slice - weakTarget) * t).round();
  if (ms < 50) ms = 50;
  return Duration(milliseconds: ms);
}

/// Build the UCI `go` command for a move request.
///
/// Prefers `movetime`. `Skill Level` weakens Stockfish's *play* but does not
/// reduce its search time, so the old fixed `go depth 15` took just as long at
/// level 7 as at level 20 — and on iOS Stockfish runs as single-threaded WASM
/// inside WebKit, where depth 15 is many seconds per move. An explicit [depth]
/// (hint/analysis) still wins.
String uciGoCommand({int? depth, Duration? moveTime, int? skillLevel}) {
  if (depth != null) return 'go depth $depth';
  final budget = moveTime ?? thinkTimeForLevel(skillLevel ?? 10);
  return 'go movetime ${budget.inMilliseconds}';
}
