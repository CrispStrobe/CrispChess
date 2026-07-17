import 'dart:async';
import 'dart:math';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'uci_position.dart';
import 'package:crisp_chess_engine/crisp_chess_engine.dart';
// Native builds get the bitboard engine here; web resolves to a stub and uses
// the chess-package search in _searchWeb instead.
import 'native_search.dart';

/// Built-in chess engine written in pure Dart.
///
/// Alpha-beta pruning + iterative deepening + transposition table +
/// quiescence search + move ordering. No native code needed.
///
/// Skill level 0-20 controls both search depth and move randomness:
/// - Level 0: depth 2, picks randomly among top-5 moves
/// - Level 10: depth 6, picks randomly among top-3 moves
/// - Level 20: depth 10, always picks the best move
class DartEngine implements ChessEngine {
  final chess.Chess _game = chess.Chess();
  AlphaBetaSearch? _search;
  bool _disposed = false;
  final _rng = Random();

  final ValueNotifier<EngineState> _stateNotifier =
      ValueNotifier(EngineState.idle);

  @override
  String get name => 'Built-in';
  @override
  String get version => '1.1.0';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 1800;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    debugPrint('[Built-in] Initialized (kIsWeb=$kIsWeb)');
    _stateNotifier.value = EngineState.ready;
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_disposed) throw StateError('Engine disposed');
    _stateNotifier.value = EngineState.thinking;

    _applyPosition(positionCommand);
    final parsed = parsePositionCommand(positionCommand);

    final skill = skillLevel ?? 10;
    final searchDepth = depth ?? _depthFromSkill(skill);
    // Always search under a time budget. Without one the isolate ran a fixed
    // depth to completion with no way to stop it — 10-25s per move on a tablet,
    // which is what read as the engine "hanging" after a few moves.
    final budget = moveTime ??
        (depth != null ? kFixedDepthTimeCap : thinkTimeForLevel(skill));

    SearchResult? result;
    if (kIsWeb) {
      result = await _searchWeb(searchDepth, budget, parsed.baseFen, parsed.moves);
    } else {
      result = await compute(
        _searchInIsolate,
        _SearchRequest(
          baseFen: parsed.baseFen,
          moves: parsed.moves,
          depth: searchDepth,
          budgetMs: budget.inMilliseconds,
        ),
      );
    }

    _stateNotifier.value = EngineState.ready;

    if (result == null) throw StateError('No legal moves');

    // At low skill levels, sometimes pick a suboptimal move
    if (skill < 20) {
      final weakened = await _weakenMove(result.bestMove, skill);
      if (weakened != null) return weakened;
    }

    return result.bestMove;
  }

  /// At low skill levels, occasionally pick a random legal move
  /// instead of the best move. Lower skill = more random.
  Future<String?> _weakenMove(String bestMove, int skill) async {
    // Probability of playing a random move (0-100%)
    // Skill 0: 60% random, Skill 10: 20% random, Skill 18+: 0%
    final randomChance = ((18 - skill) * 3.3).clamp(0, 60).toInt();
    if (_rng.nextInt(100) >= randomChance) return null; // Play best move

    // Pick a random legal move
    final moves = _game.generate_moves();
    if (moves.isEmpty) return null;
    final randomMove = moves[_rng.nextInt(moves.length)];
    final uci = '${randomMove.fromAlgebraic}${randomMove.toAlgebraic}'
        '${randomMove.promotion?.name ?? ''}';
    debugPrint('[Built-in] Weakened: $bestMove → $uci (skill=$skill)');
    return uci;
  }

  /// Web has no isolates, so step depth-by-depth and yield to the event loop
  /// between iterations to keep the UI responsive, bounded by [budget].
  ///
  /// Replays [baseFen] + [moves] to recover the game's position history, so the
  /// (chess-package) search avoids repeating positions already reached — same
  /// as the native path.
  Future<SearchResult?> _searchWeb(
      int maxDepth, Duration budget, String baseFen, List<String> moves) async {
    final webDepth = maxDepth.clamp(1, 7);
    debugPrint('[Built-in] Web search: maxDepth=$webDepth budget=${budget.inMilliseconds}ms');
    final sw = Stopwatch()..start();

    final game = chess.Chess.fromFEN(baseFen);
    final history = <int>[AlphaBetaSearch.positionKeyOf(game)];
    for (final uci in moves) {
      _playUciOn(game, uci);
      history.add(AlphaBetaSearch.positionKeyOf(game));
    }
    final search = AlphaBetaSearch(game, repetitionHistory: history);
    SearchResult? best;

    for (int d = 1; d <= webDepth; d++) {
      await Future.delayed(Duration.zero);
      if (_disposed) break;

      final remaining = budget - sw.elapsed;
      if (remaining <= Duration.zero) break;

      // Cap each iteration by the time left so one deep iteration can't
      // block the UI thread past the budget.
      final result = search.search(d, timeBudget: remaining);
      if (result != null) best = result;
      if (sw.elapsed >= budget) break;
    }

    debugPrint('[Built-in] Total: ${sw.elapsedMilliseconds}ms depth=${best?.depth}');
    return best;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {
    if (_disposed) return;
    _stateNotifier.value = EngineState.thinking;
    _applyPosition(positionCommand);
    final parsed = parsePositionCommand(positionCommand);
    final maxDepth = infinite ? 100 : (depth ?? 20);
    _search = AlphaBetaSearch(_game);

    // Cap each deepening iteration. Without this, analysis marched toward
    // depth 20 (or 100 when infinite) with each iteration searching from
    // scratch — the deep ones never return on a slow device.
    const perIteration = Duration(seconds: 3);

    for (int d = 1; d <= maxDepth; d++) {
      if (_disposed) break;
      SearchResult? result;
      if (kIsWeb) {
        await Future.delayed(Duration.zero);
        final game = chess.Chess();
        game.load(_game.fen);
        result = AlphaBetaSearch(game).search(d, timeBudget: perIteration);
      } else {
        result = await compute(
          _searchInIsolate,
          _SearchRequest(
            baseFen: parsed.baseFen,
            moves: parsed.moves,
            depth: d,
            budgetMs: perIteration.inMilliseconds,
          ),
        );
      }
      if (result == null || _disposed) break;
      yield EvalInfo(
        score: result.score / 100.0,
        depth: result.depth,
        bestMove: result.bestMove,
      );
      // Iteration hit its cap before completing depth d — going deeper would
      // only time out again, so stop here rather than spin.
      if (result.depth < d) break;
    }
    if (!_disposed) _stateNotifier.value = EngineState.ready;
  }

  @override
  void stop() => _search?.stop();

  @override
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _disposed = true;
    _search?.stop();
    _stateNotifier.value = EngineState.disposed;
  }

  void _applyPosition(String positionCommand) {
    _game.reset();
    final parts = positionCommand.split(' ');
    if (parts.length >= 2 && parts[1] == 'fen') {
      final fenEnd = parts.indexOf('moves');
      final fen = fenEnd > 0
          ? parts.sublist(2, fenEnd).join(' ')
          : parts.sublist(2).join(' ');
      _game.load(fen);
      if (fenEnd > 0) {
        for (final move in parts.sublist(fenEnd + 1)) _makeUciMove(move);
      }
    } else {
      final movesIndex = parts.indexOf('moves');
      if (movesIndex > 0) {
        for (final move in parts.sublist(movesIndex + 1)) _makeUciMove(move);
      }
    }
  }

  void _makeUciMove(String uci) => _playUciOn(_game, uci);

  static void _playUciOn(chess.Chess game, String uci) {
    if (uci.length < 4) return;
    game.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      'promotion': uci.length > 4 ? uci.substring(4, 5) : null,
    });
  }

  /// Map skill 0-20 to search depth 2-10.
  int _depthFromSkill(int skillLevel) {
    return 2 + (skillLevel * 8 ~/ 20).clamp(0, 8);
  }
}

class _SearchRequest {
  final String baseFen;
  final List<String> moves;
  final int depth;
  final int budgetMs;
  _SearchRequest({
    required this.baseFen,
    required this.moves,
    required this.depth,
    required this.budgetMs,
  });
}

SearchResult? _searchInIsolate(_SearchRequest request) {
  // Native only (compute() isolates don't exist on web). Uses the bitboard
  // engine — ~20-60x the nodes/sec of the chess-package search. The time
  // budget is what guarantees a prompt return: the isolate can't be signalled.
  // baseFen + moves let it rebuild the game history for repetition detection.
  return searchPositionNative(
      request.baseFen, request.moves, request.depth, request.budgetMs);
}
