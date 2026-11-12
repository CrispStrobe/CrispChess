import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crispchess/main.dart';
import 'package:crispchess/l10n/generated/app_localizations.dart';
import 'package:crispchess/screens/settings_screen.dart';
import 'package:crispchess/widgets/chess_board.dart';

void main() {
  setUp(
      () => SharedPreferences.setMockInitialValues({'onboarding_shown': true}));

  testWidgets('Play, Review and Train preserve board state at phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CrispChessApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.bySemanticsLabel('e2, White pawn'));
    await tester.pump();
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).selectedRow, 6);
    await tester.tap(find.text('Train'));
    await tester.pumpAndSettle();
    expect(find.text('Your daily practice'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Review a recent game'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.selectedRow, 6);
    expect(board.selectedCol, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'opponent presets save engine and strength while preserving advanced settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ghostElo': 1760});
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () async {
                      saved = await Navigator.push<Map<String, dynamic>>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen(
                                  strengthLevel: 10, hintDepth: 15)));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Around my level'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved!['engine'], 'Maia3 Dart');
    expect(saved!['strengthLevel'], 16);
    expect(saved!['maia3Variant'], '5m');
    expect(saved!['hintDepth'], 15);
    expect(tester.takeException(), isNull);
  });
}
