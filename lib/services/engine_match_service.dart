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

/// Round-robin tournament event.
class TournamentRoundStart extends MatchEvent {
  final int round;
  final int totalRounds;
  final String white;
  final String black;
  TournamentRoundStart(this.round, this.totalRounds, this.white, this.black);
}

/// Runs a round-robin tournament between 3+ engines.
///
/// Each pair plays 2 games (one as white, one as black).
class TournamentService {
  final List<ChessEngine> engines;
  final int depthPerMove;
  final _eventController = StreamController<MatchEvent>.broadcast();
  bool _stopped = false;
  final List<GameResult> results = [];

  Stream<MatchEvent> get events => _eventController.stream;

  TournamentService({required this.engines, this.depthPerMove = 8});

  /// Generate all pairings for a round-robin.
  List<(int, int)> get _pairings {
    final pairs = <(int, int)>[];
    for (int i = 0; i < engines.length; i++) {
      for (int j = i + 1; j < engines.length; j++) {
        pairs.add((i, j));
      }
    }
    return pairs;
  }

  int get totalGames => _pairings.length * 2; // 2 games per pairing

  /// Run the tournament.
  Future<List<GameResult>> run() async {
    _stopped = false;
    results.clear();

    // Initialize all engines
    for (final e in engines) {
      if (e.state == EngineState.idle) await e.initialize();
    }

    final pairings = _pairings;
    int round = 0;

    for (final (i, j) in pairings) {
      if (_stopped) break;

      // Game 1: engine[i] as white
      round++;
      _eventController.add(TournamentRoundStart(
          round, totalGames, engines[i].name, engines[j].name));

      final match1 = EngineMatchService(
        engine1: engines[i],
        engine2: engines[j],
        config: MatchConfig(numGames: 1, depthPerMove: depthPerMove, alternateColors: false),
      );
      match1.events.listen((e) => _eventController.add(e));
      final r1 = await match1.run();
      results.addAll(r1);

      if (_stopped) break;

      // Game 2: engine[j] as white
      round++;
      _eventController.add(TournamentRoundStart(
          round, totalGames, engines[j].name, engines[i].name));

      final match2 = EngineMatchService(
        engine1: engines[j],
        engine2: engines[i],
        config: MatchConfig(numGames: 1, depthPerMove: depthPerMove, alternateColors: false),
      );
      match2.events.listen((e) => _eventController.add(e));
      final r2 = await match2.run();
      results.addAll(r2);
    }

    _eventController.add(MatchFinished(results));
    return results;
  }

  void stop() {
    _stopped = true;
    for (final e in engines) {
      e.stop();
    }
  }

  void dispose() {
    _stopped = true;
    _eventController.close();
  }

  /// Get standings sorted by score (descending).
  static List<MapEntry<String, double>> standings(List<GameResult> results) {
    final scores = EngineMatchService.scores(results);
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }
}
