import 'dart:async';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import '../engines/chess_engine.dart';

/// Result of a single game in an engine match.
class GameResult {
  final String white;
  final String black;
  final String result; // "1-0", "0-1", "1/2-1/2"
  final int moves;
  final String pgn;

  GameResult({
    required this.white,
    required this.black,
    required this.result,
    required this.moves,
    required this.pgn,
  });

  double get whiteScore => result == '1-0' ? 1.0 : result == '0-1' ? 0.0 : 0.5;
  double get blackScore => 1.0 - whiteScore;
}

/// Match configuration.
class MatchConfig {
  final int numGames;
  final int depthPerMove;
  final Duration? moveTime;
  final bool alternateColors;

  const MatchConfig({
    this.numGames = 2,
    this.depthPerMove = 10,
    this.moveTime,
    this.alternateColors = true,
  });
}

/// Events emitted during a match.
sealed class MatchEvent {}

class MatchGameStarted extends MatchEvent {
  final int gameNumber;
  final String white;
  final String black;
  MatchGameStarted(this.gameNumber, this.white, this.black);
}

class MatchMovePlayed extends MatchEvent {
  final int gameNumber;
  final String move; // SAN
  final String fen;
  final bool whiteToMove;
  MatchMovePlayed(this.gameNumber, this.move, this.fen, this.whiteToMove);
}

class MatchGameFinished extends MatchEvent {
  final GameResult result;
  MatchGameFinished(this.result);
}

class MatchFinished extends MatchEvent {
  final List<GameResult> results;
  MatchFinished(this.results);
}

/// Runs engine vs engine matches.
class EngineMatchService {
  final ChessEngine engine1;
  final ChessEngine engine2;
  final MatchConfig config;
  final _eventController = StreamController<MatchEvent>.broadcast();

  bool _stopped = false;
  final List<GameResult> results = [];

  Stream<MatchEvent> get events => _eventController.stream;

  EngineMatchService({
    required this.engine1,
    required this.engine2,
    this.config = const MatchConfig(),
  });

  /// Run the match. Returns all game results.
  Future<List<GameResult>> run() async {
    _stopped = false;
    results.clear();

    // Initialize engines if needed
    if (engine1.state == EngineState.idle) await engine1.initialize();
    if (engine2.state == EngineState.idle) await engine2.initialize();

    for (int i = 0; i < config.numGames && !_stopped; i++) {
      final swapped = config.alternateColors && i.isOdd;
      final white = swapped ? engine2 : engine1;
      final black = swapped ? engine1 : engine2;
      final whiteName = white.name;
      final blackName = black.name;

      _eventController.add(MatchGameStarted(i + 1, whiteName, blackName));

      final result = await _playGame(white, black, i + 1);
      if (result != null) {
        results.add(result);
        _eventController.add(MatchGameFinished(result));
      }
    }

    _eventController.add(MatchFinished(results));
    return results;
  }

  Future<GameResult?> _playGame(
    ChessEngine white, ChessEngine black, int gameNum,
  ) async {
    final game = chess.Chess();
    int moveCount = 0;
    const maxMoves = 200; // Safety limit

    while (!game.game_over && moveCount < maxMoves && !_stopped) {
      final isWhiteTurn = game.turn == chess.Color.WHITE;
      final engine = isWhiteTurn ? white : black;

      final posCmd = game.history.isEmpty
          ? 'position startpos'
          : 'position startpos moves ${game.history.map((h) => '${h.move.fromAlgebraic}${h.move.toAlgebraic}${h.move.promotion?.name ?? ''}').join(' ')}';

      try {
        final uci = await engine.bestMove(
          posCmd,
          depth: config.depthPerMove,
          moveTime: config.moveTime,
        );

        // Parse and play the move
        if (uci.length >= 4) {
          final ok = game.move({
            'from': uci.substring(0, 2),
            'to': uci.substring(2, 4),
            'promotion': uci.length > 4 ? uci.substring(4, 5) : null,
          });
          if (ok == false) break; // Invalid move

          moveCount++;
          final sanList = game.pgn().split(RegExp(r'\s+'));
          final lastSan = sanList.isNotEmpty ? sanList.last : uci;
          _eventController.add(
            MatchMovePlayed(gameNum, lastSan, game.fen, !isWhiteTurn),
          );
        } else {
          break;
        }
      } catch (e) {
        debugPrint('[Match] Engine error: $e');
        break;
      }
    }

    if (_stopped) return null;

    // Determine result
    String result;
    if (game.in_checkmate) {
      result = game.turn == chess.Color.WHITE ? '0-1' : '1-0';
    } else {
      result = '1/2-1/2';
    }

    return GameResult(
      white: white.name,
      black: black.name,
      result: result,
      moves: moveCount,
      pgn: game.pgn(),
    );
  }

  void stop() {
    _stopped = true;
    engine1.stop();
    engine2.stop();
  }

  void dispose() {
    _stopped = true;
    _eventController.close();
  }

  /// Get aggregate scores for a list of results.
  static Map<String, double> scores(List<GameResult> results) {
    final scores = <String, double>{};
    for (final r in results) {
      scores[r.white] = (scores[r.white] ?? 0) + r.whiteScore;
      scores[r.black] = (scores[r.black] ?? 0) + r.blackScore;
    }
    return scores;
  }
}
