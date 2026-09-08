import 'package:crispchess/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final steps = duration.inMilliseconds ~/ 100;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> holdShot(WidgetTester tester, String name) async {
  debugPrint('SHOT_MARKER $name');
  await pumpFor(tester, const Duration(seconds: 4));
}

Future<void> captureLocale(
    WidgetTester tester, String language, String locale) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.clear();
  await preferences.setBool('onboarding_shown', true);
  await preferences.setString('locale', language);
  await preferences.setString('engine', 'Built-in');
  await preferences.setString('themeMode', 'light');
  app.localeNotifier.value = Locale(language);
  app.themeNotifier.value = ThemeMode.light;

  await tester.pumpWidget(const app.CrispChessApp());
  await pumpFor(tester, const Duration(seconds: 5));
  await holdShot(tester, '$locale-01-play');

  final analysis = find.byIcon(Icons.analytics_outlined);
  expect(analysis, findsOneWidget);
  await tester.tap(analysis);
  await pumpFor(tester, const Duration(seconds: 2));
  await holdShot(tester, '$locale-02-analysis');

  final menu = find.byIcon(Icons.more_vert);
  expect(menu, findsOneWidget);
  await tester.tap(menu);
  await pumpFor(tester, const Duration(seconds: 1));
  await holdShot(tester, '$locale-03-tools');

  await tester.pumpWidget(const SizedBox.shrink());
  await pumpFor(tester, const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture English and German store scenes', (tester) async {
    await captureLocale(tester, 'en', 'en-US');
    await captureLocale(tester, 'de', 'de-DE');
  });
}
