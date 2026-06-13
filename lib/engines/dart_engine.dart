import 'dart:async';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'dart_engine/search.dart';

/// Built-in chess engine written in pure Dart.
///
/// Uses alpha-beta pruning with iterative deepening, piece-square tables,
/// quiescence search, and move ordering. No native code required.
/// Estimated ~1400-1800 ELO depending on depth/time settings.
class DartEngine implements ChessEngine {
  final chess.Chess _game = chess.Chess();
  AlphaBetaSearch? _search;
  bool _disposed = false;

  final ValueNotifier<EngineState> _stateNotifier =
      ValueNotifier(EngineState.idle);

  @override
  String get name => 'CrispEngine';

  @override
  String get version => '1.0.0';

  @override
  String get license => 'MIT';

  @override
  int get estimatedElo => 1600;

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

    // Adjust depth based on skill level (0-20 scale)
    int searchDepth = depth ?? _depthFromSkill(skillLevel ?? 10);

    SearchResult? result;
    if (kIsWeb) {
      final webDepth = searchDepth.clamp(1, 4);
      debugPrint('[DartEngine] Web search: depth=$webDepth fen=${_game.fen.substring(0, 20)}...');
      await Future.delayed(Duration.zero); // yield one frame
      final sw = Stopwatch()..start();
      result = _searchInIsolate(_SearchRequest(fen: _game.fen, depth: webDepth));
      debugPrint('[DartEngine] Web search done: ${sw.elapsedMilliseconds}ms move=${result?.bestMove} nodes=${result?.nodesSearched}');
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

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) async* {
    if (_disposed) return;
    _stateNotifier.value = EngineState.thinking;

    _applyPosition(positionCommand);
    final maxDepth = depth ?? 20;

    // Run search with depth callbacks
    _search = AlphaBetaSearch(_game);

    for (int d = 1; d <= maxDepth; d++) {
      if (_disposed) break;

      SearchResult? result;
      if (kIsWeb) {
        result = _searchInIsolate(_SearchRequest(fen: _game.fen, depth: d));
      } else {
        result = await compute(
          _searchInIsolate,
          _SearchRequest(fen: _game.fen, depth: d),
        );
      }

      if (result == null || _disposed) break;

      yield EvalInfo(
        score: result.score / 100.0, // convert centipawns to pawns
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

  /// Parse a UCI position command and set up the board.
  void _applyPosition(String positionCommand) {
    _game.reset();
    final parts = positionCommand.split(' ');

    // 'position startpos' or 'position startpos moves e2e4 e7e5'
    // 'position fen ...'
    if (parts.length >= 2 && parts[1] == 'fen') {
      final fenEnd = parts.indexOf('moves');
      final fen =
          fenEnd > 0 ? parts.sublist(2, fenEnd).join(' ') : parts.sublist(2).join(' ');
      _game.load(fen);
      if (fenEnd > 0) {
        for (final move in parts.sublist(fenEnd + 1)) {
          _makeUciMove(move);
        }
      }
    } else {
      // startpos
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
    // Map 0-20 skill to 2-10 search depth
    return 2 + (skillLevel * 8 ~/ 20).clamp(0, 8);
  }
}

/// Request for isolate-based search.
class _SearchRequest {
  final String fen;
  final int depth;
  _SearchRequest({required this.fen, required this.depth});
}

/// Top-level function for compute() — runs alpha-beta in an isolate.
SearchResult? _searchInIsolate(_SearchRequest request) {
  final game = chess.Chess();
  game.load(request.fen);
  final search = AlphaBetaSearch(game);
  return search.search(request.depth);
}
