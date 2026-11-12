import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crispchess/main.dart' as app;
import 'package:crispchess/widgets/chess_board.dart';

void main() {
  testWidgets(
      'entry point loads saved platform preferences and renders the board',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'themeMode': 'dark',
      'locale': 'de',
      'onboarding_shown': true,
    });
    addTearDown(() {
      app.themeNotifier.value = ThemeMode.system;
      app.localeNotifier.value = null;
    });
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(app.themeNotifier.value, ThemeMode.dark);
    expect(app.localeNotifier.value, const Locale('de'));
    expect(find.byType(ChessBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
