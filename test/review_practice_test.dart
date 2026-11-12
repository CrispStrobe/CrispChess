import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/chess/move_analyzer.dart';
import 'package:crispchess/chess/spaced_repetition.dart';
import 'package:crispchess/controllers/game_session_controller.dart';
import 'package:crispchess/controllers/game_review_controller.dart';
import 'package:crispchess/controllers/position_game_controller.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/services/game_review_service.dart';
import 'package:crispchess/services/practice_service.dart';
import 'package:crispchess/services/preferences_service.dart';

class ReviewEngine extends ChessEngine {
  final List<EvalInfo> scores;
  final calls = <(String, int?)>[];
  final notifier = ValueNotifier(EngineState.idle);
  Completer<void>? gate;
  Completer<String>? reply;
  bool disposed = false;
  ReviewEngine(this.scores);
  @override
  String get name => 'Review fixture';
  @override
  String get version => 'test';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 1500;
  @override
  EngineState get state => notifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => notifier;
  @override
  bool get canPonder => false;
  @override
  Future<void> initialize() async {
    notifier.value = EngineState.ready;
  }

  @override
  Stream<EvalInfo> analyze(String command,
      {int? depth, bool infinite = false}) async* {
    final index = calls.length;
    calls.add((command, depth));
    if (gate != null) await gate!.future;
    yield scores[index.clamp(0, scores.length - 1)];
  }

  @override
  Future<String> bestMove(String positionCommand,
          {int? depth, Duration? moveTime, int? skillLevel}) =>
      reply?.future ?? Future.value('e7e5');
  @override
  void stop() {}
  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('the real built-in reviewer completes positions and scores checkmate',
      () async {
    final results = await GameReviewService(depth: 1)
        .review('position startpos moves f2f3 e7e5 g2g4 d8h4');
    expect(results, hasLength(4));
    expect(results.every((m) => m.annotation.evaluation.isVerified), isTrue);
    expect(results.last.annotation.evaluation.scoreAfter, -1000);
  });

  test('zero evaluations complete explicitly and keep the pre-move best move',
      () {
    final game = ChessGame();
    game.updateEvaluation(0, 'd2d4', 8);
    game.makeMove('e2e4');
    expect(game.annotations.single.evaluation.isComplete, isFalse);
    game.updateEvaluation(0, 'e7e5', 8);
    final evaluation = game.annotations.single.evaluation;
    expect(evaluation.isComplete, isTrue);
    expect(evaluation.scoreBefore, 0);
    expect(evaluation.scoreAfter, 0);
    expect(evaluation.bestMove, 'd2d4');
    expect(game.currentNode.annotation!.evaluation, same(evaluation));
    game.dispose();
  });

  test('a move made without a baseline stays unclassified', () {
    final game = ChessGame()..makeMove('e2e4');
    game.updateEvaluation(4, 'e7e5', 8);
    expect(game.annotations.single.evaluation.isComplete, isFalse);
    expect(game.annotations.single.evaluation.quality, MoveQuality.neutral);
    game.dispose();
  });

  test('review compares one engine/depth and saves Black mistakes only, once',
      () async {
    final engine = ReviewEngine([
      const EvalInfo(score: 0, depth: 8, bestMove: 'e2e4'),
      const EvalInfo(
          score: 0, depth: 8, bestMove: 'e7e5', pv: 'e7e5 g1f3 b8c6'),
      const EvalInfo(score: 3, depth: 8, bestMove: 'd2d4'),
    ]);
    final results = await GameReviewService(engine: engine)
        .review('position startpos moves e2e4 f7f6');
    expect(engine.calls.map((c) => c.$2), everyElement(8));
    expect(
        results.map((m) => m.annotation.evaluation.whiteToMove), [true, false]);
    expect(results.last.continuation, ['e7e5', 'g1f3', 'b8c6']);
    final prefs = PreferencesService();
    await prefs.init();
    final practice = PracticeService(prefs);
    expect(practice.collect(results, playerIsWhite: true), 0);
    expect(practice.collect(results, playerIsWhite: false), 1);
    final first = practice.items.single;
    practice.record(first, correct: true);
    expect(practice.collect(results, playerIsWhite: false), 0);
    final restartedPrefs = PreferencesService();
    await restartedPrefs.init();
    final restarted = PracticeService(restartedPrefs).items.single;
    expect(restarted.solution, 'e7e5');
    expect(restarted.fen.split(' ')[1], 'b');
    expect(restarted.attempts, 1);
    expect(restarted.nextReview.isAfter(DateTime.now()), isTrue);
    expect(engine.disposed, isTrue);
  });

  test('a shallow review cannot produce accuracy/training evidence', () async {
    final engine = ReviewEngine([
      const EvalInfo(score: 0, depth: 3, bestMove: 'd2d4'),
      const EvalInfo(score: -5, depth: 8, bestMove: 'e7e5'),
    ]);
    final results = await GameReviewService(engine: engine)
        .review('position startpos moves e2e4');
    expect(results.single.annotation.evaluation.isVerified, isFalse);
    final prefs = PreferencesService();
    await prefs.init();
    expect(PracticeService(prefs).collect(results, playerIsWhite: true), 0);
  });

  test('a custom position starting with Black retains side to move', () async {
    const fen = '4k3/8/8/8/8/8/4P3/4K3 b - - 0 12';
    final engine = ReviewEngine([
      const EvalInfo(score: 1, depth: 8, bestMove: 'e8d7'),
      const EvalInfo(score: 1, depth: 8, bestMove: 'e2e4'),
    ]);
    final results = await GameReviewService(engine: engine)
        .review('position fen $fen moves e8d7');
    expect(results.single.annotation.evaluation.whiteToMove, isFalse);
    expect(results.single.fen, fen);
  });

  test('cancelling a review discards late results and releases the engine',
      () async {
    final engine =
        ReviewEngine([const EvalInfo(score: 0, depth: 8, bestMove: 'e2e4')]);
    engine.gate = Completer<void>();
    final controller = GameReviewController(
        createService: () => GameReviewService(engine: engine));
    final task =
        controller.start('position startpos moves e2e4', playerIsWhite: true);
    await Future<void>.delayed(Duration.zero);
    controller.cancel();
    engine.gate!.complete();
    await task;
    expect(controller.review, isNull);
    expect(controller.running, isFalse);
    expect(engine.disposed, isTrue);
    controller.dispose();
  });

  test('spaced repetition tests recall after each interval including 30 days',
      () {
    var at = DateTime.utc(2026, 1, 1);
    final item = SrItem(fen: 'unused', solution: 'unused', description: '');
    for (final days in [1, 3, 7, 14, 30]) {
      item.markCorrect(now: at);
      expect(item.nextReview.difference(at).inDays, days);
      expect(item.isLearned, isFalse);
      at = item.nextReview;
    }
    item.markCorrect(now: at);
    expect(item.isLearned, isTrue);
    item.markIncorrect(now: at);
    expect(item.isLearned, isFalse);
    expect(item.nextReview.difference(at).inDays, 1);
  });

  test(
      'session restoration preserves custom roots and completion is idempotent',
      () async {
    final prefs = PreferencesService();
    await prefs.init();
    final session = GameSessionController(prefs);
    final game = ChessGame()..loadFen('4k3/8/8/8/8/8/4P3/4K3 b - - 0 12');
    game.makeMove('e8d7');
    session.save(game);
    final restored = ChessGame();
    expect(session.restore(restored), ['e8d7']);
    expect(restored.currentFEN, game.currentFEN);
    session.finish(game,
        engineName: 'Fixture',
        playAsBlack: true,
        twoPlayer: false,
        strengthLevel: 10);
    session.finish(game,
        engineName: 'Fixture',
        playAsBlack: true,
        twoPlayer: false,
        strengthLevel: 10);
    expect(prefs.gamesPlayed, 1);
    expect(prefs.gameHistory, hasLength(1));
    expect(prefs.hasSavedGame, isFalse);
    restored.dispose();
    game.dispose();
  });

  test('late Ghost replies cannot mutate a disposed practice game', () async {
    final engine = ReviewEngine([])..reply = Completer<String>();
    final c = PositionGameController(ChessGame().currentFEN, engine: engine);
    await c.initialize();
    final task = c.move('e2e4');
    await Future<void>.delayed(Duration.zero);
    expect(c.thinking, isTrue);
    c.dispose();
    engine.reply!.complete('e7e5');
    await task;
    expect(c.game.moveHistory, ['e2e4']);
    expect(engine.disposed, isTrue);
  });
}
