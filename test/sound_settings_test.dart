import 'package:crispchess/l10n/generated/app_localizations.dart';
import 'package:crispchess/screens/chess_game_screen.dart';
import 'package:crispchess/screens/settings_screen.dart';
import 'package:crispchess/services/preferences_service.dart';
import 'package:crispchess/services/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget localizedApp(Widget home, {String language = 'en'}) => MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Finder get soundToggle => find.byKey(const ValueKey('soundEnabled'));

Future<void> showSoundToggle(WidgetTester tester) async {
  await tester.scrollUntilVisible(soundToggle, 400,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_shown': true});
  });

  for (final (language, label, subtitle) in [
    ('en', 'Sound Effects', 'Play sounds for moves and game events'),
    ('de', 'Soundeffekte', 'Töne für Züge und Spielereignisse abspielen'),
  ]) {
    testWidgets(
        '$language toggle loads disabled preference with localized text',
        (tester) async {
      SharedPreferences.setMockInitialValues({'soundEnabled': false});
      await tester.pumpWidget(localizedApp(
        const SettingsScreen(strengthLevel: 10, hintDepth: 15),
        language: language,
      ));
      await tester.pumpAndSettle();
      await showSoundToggle(tester);
      expect(find.text(label), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);
      expect(tester.widget<SwitchListTile>(soundToggle).value, isFalse);
      await tester.tap(soundToggle);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(soundToggle).value, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Save persists and immediately applies mute and re-enable in game',
      (tester) async {
    final sound = SoundService();
    await tester.pumpWidget(localizedApp(ChessGameScreen(soundService: sound)));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(sound.enabled, isTrue);

    for (final enabled in [false, true]) {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await showSoundToggle(tester);
      // Reopening also verifies that the previously saved value was loaded.
      expect(tester.widget<SwitchListTile>(soundToggle).value, !enabled);
      await tester.tap(soundToggle);
      await tester.pump();
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Save'));
      await tester.pumpAndSettle();
      expect(sound.enabled, enabled);
      final preferences = PreferencesService();
      await preferences.init();
      expect(preferences.soundEnabled, enabled);
      expect((await SharedPreferences.getInstance()).getBool('soundEnabled'),
          enabled);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving settings without Save preserves the stored setting',
      (tester) async {
    final sound = SoundService();
    await tester.pumpWidget(localizedApp(ChessGameScreen(soundService: sound)));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await showSoundToggle(tester);
    await tester.tap(soundToggle);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(sound.enabled, isTrue);
    final preferences = PreferencesService();
    await preferences.init();
    expect(preferences.soundEnabled, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
