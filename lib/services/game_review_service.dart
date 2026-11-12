import 'package:chess/chess.dart' as chess;

import '../chess/move_analyzer.dart';
import '../engines/chess_engine.dart';
import '../engines/dart_engine.dart';
import '../engines/uci_position.dart';

class ReviewedMove {
  final int ply;
  final String positionCommand;
  final String fen;
  final MoveAnnotation annotation;
  final List<String> continuation;

  const ReviewedMove(
      {required this.ply,
      required this.positionCommand,
      required this.fen,
      required this.annotation,
      required this.continuation});
}

/// Independent of the opponent and live eval stream. Every adjacent position
/// uses one engine and the same depth. A shallow/timed-out search stays pending.
class GameReviewService {
  final ChessEngine _engine;
  final int depth;
  bool _cancelled = false;

  GameReviewService({ChessEngine? engine, this.depth = 8})
      : _engine = engine ?? DartEngine();

  void cancel() {
    _cancelled = true;
    _engine.stop();
  }

  Future<EvalInfo?> _evaluate(String command) async {
    if (_cancelled) return null;
    final board = chess.Chess.fromFEN(fenFromPositionCommand(command));
    if (board.game_over) {
      return EvalInfo(
          score: board.in_checkmate
              ? (board.turn == chess.Color.WHITE ? -1000 : 1000)
              : 0,
          depth: depth);
    }
    EvalInfo? result;
    await for (final info in _engine.analyze(command, depth: depth)) {
      if (_cancelled) return null;
      if (info.pvIndex == 1) result = info;
    }
    return result;
  }

  Future<List<ReviewedMove>> review(
    String positionCommand, {
    void Function(int done, int total)? onProgress,
  }) async {
    final parsed = parsePositionCommand(positionCommand);
    final results = <ReviewedMove>[];
    String at(int ply) => 'position fen ${parsed.baseFen}'
        '${ply == 0 ? '' : ' moves ${parsed.moves.take(ply).join(' ')}'}';
    try {
      await _engine.initialize();
      if (_cancelled) return results;
      if (_engine.state != EngineState.ready)
        throw StateError('Review engine unavailable');
      var before = await _evaluate(at(0));
      for (var ply = 0; ply < parsed.moves.length && !_cancelled; ply++) {
        final fen = fenFromPositionCommand(at(ply));
        final board = chess.Chess.fromFEN(fen);
        final after = await _evaluate(at(ply + 1));
        if (_cancelled) break;
        final complete = before != null &&
            after != null &&
            before.depth >= depth &&
            after.depth >= depth &&
            before.score.isFinite &&
            after.score.isFinite;
        final evaluation = MoveEvaluation(
          scoreBefore: before?.score ?? 0,
          scoreAfter: after?.score ?? 0,
          bestMove: before?.bestMove ?? '',
          bestMoveScore: before?.score ?? 0,
          depth: (before?.depth ?? 0) < (after?.depth ?? 0)
              ? before?.depth ?? 0
              : after?.depth ?? 0,
          whiteToMove: board.turn == chess.Color.WHITE,
          isComplete: complete,
          isVerified: complete,
        );
        // Keep only a legal continuation, including a single best move when
        // an engine provides no PV. Never save a reply from the played line.
        final line = <String>[];
        final pv = before?.pv?.split(' ');
        final candidate =
            pv != null && pv.isNotEmpty && pv.first == before?.bestMove
                ? pv
                : [before?.bestMove ?? ''];
        for (final move in candidate) {
          if (move.length < 4 ||
              !board.move({
                'from': move.substring(0, 2),
                'to': move.substring(2, 4),
                if (move.length == 5) 'promotion': move[4]
              })) break;
          line.add(move);
        }
        // The built-in engine reports a best move rather than a PV. Extend
        // costly misses into a short legal line the player can replay.
        while (line.isNotEmpty &&
            line.length < 3 &&
            complete &&
            evaluation.centipawnLoss >= 1 &&
            evaluation.bestMove != parsed.moves[ply] &&
            !board.game_over &&
            !_cancelled) {
          final command = 'position fen ${parsed.baseFen} moves '
              '${[...parsed.moves.take(ply), ...line].join(' ')}';
          final next = await _evaluate(command);
          final move = next?.bestMove;
          if (move == null ||
              move.length < 4 ||
              !board.move({
                'from': move.substring(0, 2),
                'to': move.substring(2, 4),
                if (move.length == 5) 'promotion': move[4],
              })) break;
          line.add(move);
        }
        if (_cancelled) break;
        results.add(ReviewedMove(
            ply: ply,
            positionCommand: at(ply),
            fen: fen,
            annotation: MoveAnalyzer(chess.Chess.fromFEN(fen)).analyzeMove(
                uciMove: parsed.moves[ply], evaluation: evaluation),
            continuation: line));
        before = after;
        onProgress?.call(ply + 1, parsed.moves.length);
      }
      return results;
    } finally {
      _engine.dispose();
    }
  }
}
