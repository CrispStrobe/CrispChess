import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/chess_game_screen.dart';

/// Global theme notifier — settings screen updates this, app rebuilds.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Global locale notifier — null means system default.
final localeNotifier = ValueNotifier<Locale?>(null);

void main() {
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Load saved theme and locale before app starts
  SharedPreferences.getInstance().then((prefs) {
    final theme = prefs.getString('themeMode') ?? 'system';
    themeNotifier.value = switch (theme) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final lang = prefs.getString('locale');
    if (lang != null && lang != 'system') {
      localeNotifier.value = Locale(lang);
    }
  });

  runApp(const CrispChessApp());
}

class CrispChessApp extends StatelessWidget {
  const CrispChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale?>(
          valueListenable: localeNotifier,
          builder: (context, locale, _) {
        return MaterialApp(
          title: 'CrispChess',
          locale: locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('de'),
          ],
          theme: ThemeData(
            colorSchemeSeed: Colors.brown,
            brightness: Brightness.light,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.brown,
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.black,
          ),
          themeMode: themeMode,
          home: const ChessGameScreen(),
        );
          },
        );
      },
    );
  }
}
