import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:crispchess/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('entry point restores platform preferences before interacting',
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
    // Exercise the entry point, rather than bypassing bootstrap with the app widget.
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(app.themeNotifier.value, ThemeMode.dark);
    expect(app.localeNotifier.value, const Locale('de'));
    expect(find.text('Spielen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('App builds without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const app.CrispChessApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // App should render without throwing
    expect(tester.takeException(), isNull);
  });
}
