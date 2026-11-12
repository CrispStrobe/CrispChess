import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/chess/spaced_repetition.dart';
import 'package:crispchess/l10n/generated/app_localizations.dart';
import 'package:crispchess/screens/practice_screen.dart';
import 'package:crispchess/screens/game_summary_screen.dart';
import 'package:crispchess/screens/training_hub_screen.dart';
import 'package:crispchess/chess/move_analyzer.dart';
import 'package:crispchess/widgets/chess_board.dart';
import 'package:crispchess/widgets/position_board.dart';
import 'package:crispchess/widgets/capture_effect.dart';
import 'package:crispchess/services/preferences_service.dart';
import 'package:crispchess/services/practice_service.dart';

Widget app(Widget child, {String locale = 'en'}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale(locale),
    home: child);

Future<void> square(WidgetTester tester, String name) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^$name,')));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a saved mistake can be solved, replayed and scheduled',
      (tester) async {
    final game = ChessGame();
    final item = SrItem(
        fen: game.currentFEN,
        solution: 'e2e4',
        description: 'd2d3',
        continuation: ['e2e4', 'e7e5', 'g1f3']);
    game.dispose();
    await tester.pumpWidget(app(PracticeScreen(initialItem: item)));
    await tester.pumpAndSettle();
    await square(tester, 'e2');
    await square(tester, 'e4');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -340));
    await tester.pumpAndSettle();
    expect(find.textContaining('Correct.'), findsOneWidget);
    expect(find.text('e4 e5 Nf3'), findsOneWidget);
    expect(find.text('Replay against my Ghost'), findsOneWidget);
    final prefs = PreferencesService();
    await prefs.init();
    final saved = PracticeService(prefs).items.single;
    expect(saved.timesCorrect, 1);
    expect(saved.isDue, isFalse);
    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    final board = tester.widget<PositionBoard>(find.byType(PositionBoard));
    expect(board.game.moveHistory, ['e2e4', 'e7e5']);
  });

  testWidgets(
      'a wrong attempt then correction schedules another recall tomorrow',
      (tester) async {
    final game = ChessGame();
    await tester.pumpWidget(app(PracticeScreen(
        initialItem:
            SrItem(fen: game.currentFEN, solution: 'e2e4', description: ''))));
    await tester.pumpAndSettle();
    await square(tester, 'd2');
    await square(tester, 'd4');
    await square(tester, 'e2');
    await square(tester, 'e4');
    await tester.pumpAndSettle();
    final prefs = PreferencesService();
    await prefs.init();
    final item = PracticeService(prefs).items.single;
    expect(item.attempts, 1);
    expect(item.correctAttempts, 0);
    expect(item.timesCorrect, 0);
    game.dispose();
  });

  testWidgets('summary accuracy follows recorded Black side, not list parity',
      (tester) async {
    MoveAnnotation annotation(bool white, double after) => MoveAnnotation(
        move: 'test',
        evaluation: MoveEvaluation(
            scoreBefore: 0,
            scoreAfter: after,
            bestMove: 'test',
            bestMoveScore: 0,
            depth: 8,
            whiteToMove: white,
            isVerified: true),
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.opening);
    await tester.pumpWidget(app(GameSummaryScreen(
        movesSan: const ['e4', 'e5'],
        evalHistory: const [],
        annotations: [annotation(true, -4), annotation(false, 0)],
        gameResult: '*',
        engineName: 'Fixture',
        playerIsWhite: false)));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('keyboard selects and moves a piece without pointer input',
      (tester) async {
    final game = ChessGame();
    await tester.pumpWidget(
        app(Scaffold(body: PositionBoard(game: game, onMove: game.makeMove))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // Initial keyboard square a1 -> e2.
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(game.moveHistory, ['e2e4']);
    await tester.pumpWidget(const SizedBox.shrink());
    game.dispose();
  });

  testWidgets(
      'square semantics are localized and blindfold hides piece identities',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final game = ChessGame();
    Widget board(bool blindfold) => app(
        Scaffold(
            body: ChessBoard(
                board: game.board,
                whiteToMove: true,
                squareToAlgebraic: game.squareToAlgebraic,
                blindfold: blindfold)),
        locale: 'de');
    await tester.pumpWidget(board(false));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('e2, Weiß Bauer'), findsOneWidget);
    await tester.pumpWidget(board(true));
    await tester.pump();
    expect(find.bySemanticsLabel('e2, Weiß Bauer'), findsNothing);
    expect(find.bySemanticsLabel('e2'), findsOneWidget);
    semantics.dispose();
    game.dispose();
  });

  testWidgets('reduced motion suppresses move slides and capture particles',
      (tester) async {
    final game = ChessGame();
    Widget board(String? move) => app(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
            body: ChessBoard(
                board: game.board,
                whiteToMove: game.whiteToMove,
                squareToAlgebraic: game.squareToAlgebraic,
                lastMoveUci: move,
                isCapture: true))));
    await tester.pumpWidget(board(null));
    await tester.pumpAndSettle();
    game.makeMove('e2e4');
    await tester.pumpWidget(board('e2e4'));
    await tester.pump();
    expect(find.byType(CaptureEffect), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    game.dispose();
  });

  testWidgets('training entry points render in German at phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const TrainingHubScreen(), locale: 'de'));
    await tester.pumpAndSettle();
    expect(find.text('Dein tägliches Training'), findsOneWidget);
    expect(find.text('Fünf Aufgaben lösen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
