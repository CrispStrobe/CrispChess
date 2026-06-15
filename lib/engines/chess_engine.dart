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
