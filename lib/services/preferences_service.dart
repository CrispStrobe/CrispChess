/// Persistent player preferences — survives app restarts.
///
/// Uses shared_preferences (works on all Flutter platforms including web).
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/chess_clock.dart';

class PreferencesService {
  static const _keyEngine = 'engine';
  static const _keyVariant = 'variant';
  static const _keyStrength = 'strength';
  static const _keyHintDepth = 'hintDepth';
  static const _keyAnimSpeed = 'animationSpeed';
  static const _keyPlayAsBlack = 'playAsBlack';
  static const _keyPieceTheme = 'pieceTheme';
  static const _keyTimeControl = 'timeControl';
  static const _keySoundEnabled = 'soundEnabled';
  static const _keyShowValidMoves = 'showValidMoves';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Engine
  String get engine => _prefs?.getString(_keyEngine) ?? 'Built-in';
  set engine(String v) => _prefs?.setString(_keyEngine, v);

  // Variant (used for Maia3/Lc0/Stockfish sub-selection)
  String get variant => _prefs?.getString(_keyVariant) ?? '5m';
  set variant(String v) => _prefs?.setString(_keyVariant, v);

  // Strength level (0-20)
  int get strengthLevel => _prefs?.getInt(_keyStrength) ?? 10;
  set strengthLevel(int v) => _prefs?.setInt(_keyStrength, v);

  // Hint depth
  int get hintDepth => _prefs?.getInt(_keyHintDepth) ?? 15;
  set hintDepth(int v) => _prefs?.setInt(_keyHintDepth, v);

  // Animation speed (0=instant, 1=fast, 2=normal, 3=slow)
  int get animationSpeed => _prefs?.getInt(_keyAnimSpeed) ?? 2;
  set animationSpeed(int v) => _prefs?.setInt(_keyAnimSpeed, v);

  // Play as black
  bool get playAsBlack => _prefs?.getBool(_keyPlayAsBlack) ?? false;
  set playAsBlack(bool v) => _prefs?.setBool(_keyPlayAsBlack, v);

  // Piece theme
  String get pieceTheme => _prefs?.getString(_keyPieceTheme) ?? 'chessnut';
  set pieceTheme(String v) => _prefs?.setString(_keyPieceTheme, v);

  // Time control (stored as enum name)
  TimeControl get timeControl {
    final name = _prefs?.getString(_keyTimeControl);
    if (name == null) return TimeControl.unlimited;
    return TimeControl.values.firstWhere(
      (tc) => tc.name == name,
      orElse: () => TimeControl.unlimited,
    );
  }
  set timeControl(TimeControl v) => _prefs?.setString(_keyTimeControl, v.name);

  // Sound
  bool get soundEnabled => _prefs?.getBool(_keySoundEnabled) ?? true;
  set soundEnabled(bool v) => _prefs?.setBool(_keySoundEnabled, v);

  // Show valid moves
  bool get showValidMoves => _prefs?.getBool(_keyShowValidMoves) ?? true;
  set showValidMoves(bool v) => _prefs?.setBool(_keyShowValidMoves, v);

  /// Reset all preferences to defaults.
  Future<void> resetToDefaults() async {
    await _prefs?.clear();
  }
}
