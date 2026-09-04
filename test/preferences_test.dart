import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crispchess/services/preferences_service.dart';
import 'package:crispchess/chess/chess_clock.dart';

void main() {
  group('PreferencesService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns defaults before init', () {
      final prefs = PreferencesService();
      expect(prefs.engine, 'Built-in');
      expect(prefs.variant, '5m');
      expect(prefs.strengthLevel, 10);
      expect(prefs.animationSpeed, 2);
      expect(prefs.playAsBlack, false);
      expect(prefs.pieceTheme, 'chessnut');
      expect(prefs.soundEnabled, true);
      expect(prefs.showValidMoves, true);
      expect(prefs.timeControl, TimeControl.unlimited);
      expect(prefs.lc0Backend, 'auto');
    });

    test('persists engine choice', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.engine = 'Stockfish';
      expect(prefs.engine, 'Stockfish');
    });

    test('persists Lc0 inference backend', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.lc0Backend = 'dart';
      expect(prefs.lc0Backend, 'dart');
    });

    test('persists strength level', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.strengthLevel = 15;
      expect(prefs.strengthLevel, 15);
    });

    test('persists play as black', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.playAsBlack = true;
      expect(prefs.playAsBlack, true);
    });

    test('persists time control', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.timeControl = TimeControl.blitz5;
      expect(prefs.timeControl, TimeControl.blitz5);
    });

    test('persists piece theme', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.pieceTheme = 'fantasy';
      expect(prefs.pieceTheme, 'fantasy');
    });

    test('resetToDefaults clears everything', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.engine = 'Stockfish';
      prefs.strengthLevel = 20;
      prefs.playAsBlack = true;

      await prefs.resetToDefaults();

      // After reset, should return defaults
      final fresh = PreferencesService();
      await fresh.init();
      expect(fresh.engine, 'Built-in');
      expect(fresh.strengthLevel, 10);
      expect(fresh.playAsBlack, false);
    });

    test('persists variant', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.variant = '79m';
      expect(prefs.variant, '79m');
    });

    test('persists animation speed', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.animationSpeed = 0;
      expect(prefs.animationSpeed, 0);
    });

    test('handles unknown time control gracefully', () async {
      SharedPreferences.setMockInitialValues({'timeControl': 'nonexistent'});
      final prefs = PreferencesService();
      await prefs.init();
      expect(prefs.timeControl, TimeControl.unlimited);
    });
  });
}
