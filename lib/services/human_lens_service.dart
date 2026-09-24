import 'dart:async';

import 'package:chess/chess.dart' as chess_lib;

import '../chess/human_lens.dart';
import '../chess/player_profile.dart';
import '../engines/chess_engine.dart';
import '../engines/dart_engine.dart';
import '../engines/maia3_dart_engine.dart';
import '../engines/uci_position.dart';

/// The engines behind the Human Lens, loaded once and kept for the session.
///
/// Maia (what humans play) is the 5M model: 25 MB, downloaded on first use and
/// cached, fast enough to run the rating ladder on a phone. The verdicts come
/// from the built-in engine — it runs on every platform, web included, in a
/// worker isolate, so it never blocks the board. It is not Stockfish, but
/// telling a two-pawn blunder from a sound move does not need Stockfish.
class HumanLensService {
  HumanLensService._();
  static final HumanLensService instance = HumanLensService._();

  Maia3DartEngine? _maia;
  DartEngine? _judge;
  Future<void>? _loading;

  /// Serialises every request: both engines are single-occupancy.
  Future<void> _queue = Future.value();

  bool get isLoaded => _maia?.state == EngineState.ready;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final maia = Maia3DartEngine(variantId: '5m');
    final judge = DartEngine();
    try {
      await Future.wait([maia.initialize(), judge.initialize()]);
    } catch (_) {
      _loading = null;
      rethrow;
    }
    if (maia.state != EngineState.ready) {
      _loading = null;
      maia.dispose();
      judge.dispose();
      throw StateError('The Maia model could not be loaded. It is downloaded '
          'once (25 MB) — check the connection and try again.');
    }
    _maia = maia;
    _judge = judge;
  }

  /// Human Lens for a single position.
  Future<HumanLensReport> analyzePosition(String positionCommand,
          {required int elo}) =>
      _exclusive(() => _lens(defaultEloLadder, depth: 8)
          .analyzePosition(positionCommand, elo: elo));

  /// Rungs used when a whole game is reviewed — fewer than for one position,
  /// because every one of them costs a model pass per move.
  static const List<int> reviewLadder = [1000, 1500, 2000];

  /// Human review of the moves at [plies] of the game [positionCommand]
  /// (the command for the *final* position, carrying the full move list).
  Future<List<HumanMoveReview>> reviewGame(
    String positionCommand, {
    required List<int> plies,
    required int elo,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) =>
      _exclusive(() {
        final parsed = parsePositionCommand(positionCommand);
        final base = parsed.baseFen == _startFen
            ? 'position startpos'
            : 'position fen ${parsed.baseFen}';
        String before(int ply) => ply == 0
            ? base
            : '$base moves ${parsed.moves.take(ply).join(' ')}';
        final valid = [for (final p in plies) if (p < parsed.moves.length) p];
        return _lens(reviewLadder, depth: 6).reviewMoves(
          plies: valid,
          positionCommands: [for (final p in valid) before(p)],
          played: [for (final p in valid) parsed.moves[p]],
          elo: elo,
          onProgress: onProgress,
          cancelled: cancelled,
        );
      });

  /// The rating whose players' choices best explain [moves] — Maia's
  /// probability of each move across the rating ladder, no engine needed.
  /// Uses at most [maxMoves] of them (the first ones: newest games first).
  Future<int?> estimatePlayerElo(
    List<PlayerMove> moves, {
    int maxMoves = 120,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) =>
      _exclusive(() async {
        final use = moves.take(maxMoves).toList();
        final reviews = <HumanMoveReview>[];
        for (var i = 0; i < use.length; i++) {
          if (cancelled?.call() ?? false) break;
          final byElo = <int, double>{};
          for (final e in defaultEloLadder) {
            final p = await _maia!.movePolicy(use[i].positionCommand, elo: e);
            byElo[e] = p[use[i].move] ?? 0;
          }
          reviews.add(HumanMoveReview(
            ply: i,
            played: use[i].move,
            bestMove: null,
            playedProbability: 0,
            bestProbability: 0,
            playedByElo: byElo,
          ));
          onProgress?.call(i + 1, use.length);
        }
        return estimateElo(reviews);
      });

  HumanLens _lens(List<int> ladder, {required int depth}) => HumanLens(
        ladder: ladder,
        policy: (cmd, elo) => _maia!.movePolicy(cmd, elo: elo),
        evaluate: (cmd) => _evaluate(cmd, depth),
      );

  Future<({double score, String? bestMove})> _evaluate(
      String cmd, int depth) async {
    // The search has nothing to say once the game is over; score it directly.
    final board = chess_lib.Chess.fromFEN(fenFromPositionCommand(cmd));
    if (board.in_checkmate) {
      return (
        score: board.turn == chess_lib.Color.WHITE ? -20.0 : 20.0,
        bestMove: null
      );
    }
    if (board.game_over) return (score: 0.0, bestMove: null);

    EvalInfo? last;
    await for (final info in _judge!.analyze(cmd, depth: depth)) {
      last = info;
    }
    return (score: last?.score ?? 0.0, bestMove: last?.bestMove);
  }

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    await ensureLoaded();
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      return await body();
    } finally {
      done.complete();
    }
  }

  static const String _startFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
}
