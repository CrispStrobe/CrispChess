import 'dart:async';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'dart_engine/search.dart';

/// Built-in chess engine written in pure Dart.
///
/// Uses alpha-beta pruning with iterative deepening, piece-square tables,
/// quiescence search, transposition table, and move ordering.
/// No native code required — works on all platforms including web.
class DartEngine implements ChessEngine {
  final chess.Chess _game = chess.Chess();
  AlphaBetaSearch? _search;
  bool _disposed = false;

  final ValueNotifier<EngineState> _stateNotifier =
      ValueNotifier(EngineState.idle);

  @override
  String get name => 'CrispEngine';

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
    debugPrint('[DartEngine] Initialized (kIsWeb=$kIsWeb)');
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

    int searchDepth = depth ?? _depthFromSkill(skillLevel ?? 10);

    SearchResult? result;
    if (kIsWeb) {
      result = await _searchWeb(searchDepth);
    } else {
      result = await compute(
        _searchInIsolate,
        _SearchRequest(fen: _game.fen, depth: searchDepth),
      );
    }

    _stateNotifier.value = EngineState.ready;

    if (result == null) throw StateError('No legal moves');
    return result.bestMove;
  }

  /// Non-blocking incremental search for web.
  /// Runs one depth at a time, yielding to the UI between each.
  Future<SearchResult?> _searchWeb(int maxDepth) async {
    final webDepth = maxDepth.clamp(1, 7);
    debugPrint('[DartEngine] Web incremental search: maxDepth=$webDepth');
    final sw = Stopwatch()..start();

    final game = chess.Chess();
    game.load(_game.fen);
    final search = AlphaBetaSearch(game);
    SearchResult? best;

    for (int d = 1; d <= webDepth; d++) {
      // Yield to UI between each depth iteration
      await Future.delayed(Duration.zero);
      if (_disposed) break;

      final depthSw = Stopwatch()..start();
      final result = search.search(d);
      if (result != null) {
        best = result;
        debugPrint('[DartEngine] depth=$d: ${result.bestMove} score=${result.score} nodes=${result.nodesSearched} ${depthSw.elapsedMilliseconds}ms');
      }

      // If any single depth takes >500ms, stop — deeper will be too slow
      if (depthSw.elapsedMilliseconds > 500) {
        debugPrint('[DartEngine] Stopping: depth $d took ${depthSw.elapsedMilliseconds}ms');
        break;
      }
    }

    debugPrint('[DartEngine] Total: ${sw.elapsedMilliseconds}ms move=${best?.bestMove}');
    return best;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) async* {
    if (_disposed) return;
    _stateNotifier.value = EngineState.thinking;

    _applyPosition(positionCommand);
    final maxDepth = depth ?? 20;

    _search = AlphaBetaSearch(_game);

    for (int d = 1; d <= maxDepth; d++) {
      if (_disposed) break;

      SearchResult? result;
      if (kIsWeb) {
        await Future.delayed(Duration.zero);
        final game = chess.Chess();
        game.load(_game.fen);
        result = AlphaBetaSearch(game).search(d);
      } else {
        result = await compute(
          _searchInIsolate,
          _SearchRequest(fen: _game.fen, depth: d),
        );
      }

      if (result == null || _disposed) break;

      yield EvalInfo(
        score: result.score / 100.0,
        depth: result.depth,
        bestMove: result.bestMove,
      );
    }

    if (!_disposed) _stateNotifier.value = EngineState.ready;
  }

  @override
  void stop() {
    _search?.stop();
  }

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
        for (final move in parts.sublist(fenEnd + 1)) {
          _makeUciMove(move);
        }
      }
    } else {
      final movesIndex = parts.indexOf('moves');
      if (movesIndex > 0) {
        for (final move in parts.sublist(movesIndex + 1)) {
          _makeUciMove(move);
        }
      }
    }
  }

  void _makeUciMove(String uci) {
    if (uci.length < 4) return;
    _game.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      'promotion': uci.length > 4 ? uci.substring(4, 5) : null,
    });
  }

  int _depthFromSkill(int skillLevel) {
    return 2 + (skillLevel * 8 ~/ 20).clamp(0, 8);
  }
}

class _SearchRequest {
  final String fen;
  final int depth;
  _SearchRequest({required this.fen, required this.depth});
}

SearchResult? _searchInIsolate(_SearchRequest request) {
  final game = chess.Chess();
  game.load(request.fen);
  final search = AlphaBetaSearch(game);
  return search.search(request.depth);
}
