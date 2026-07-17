/// Persistent player preferences — survives app restarts.
///
/// Uses shared_preferences (works on all Flutter platforms including web).
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/chess_clock.dart';
import '../chess/game_state.dart' show ChessVariant;

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
  static const _keyChessVariant = 'chessVariant';
  static const _keyCustomBaseMinutes = 'customBaseMinutes';
  static const _keyCustomIncrementSeconds = 'customIncrementSeconds';
  static const _keyEngineHashMb = 'engineHashMb';
  static const _keyEngineThreads = 'engineThreads';
  static const _keyBoardTheme = 'boardTheme';
  static const _keyNotationStyle = 'notationStyle';
  static const _keyBlindfold = 'blindfold';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Engine
  String get engine => migrateEngineName(_prefs?.getString(_keyEngine)) ?? 'Built-in';
  set engine(String v) => _prefs?.setString(_keyEngine, v);

  /// Maps removed engine names onto their replacements.
  ///
  /// 'Maia3' was a separate JS-bridge engine: web-only, and a stub that threw
  /// on native. 'Maia3 Dart' is the same model via the pure-Dart ONNX
  /// interpreter and works everywhere, so anyone who had the old one selected
  /// is moved across rather than silently dropped back to the built-in engine
  /// (and a stale value would crash the settings dropdown).
  static String? migrateEngineName(String? name) =>
      name == 'Maia3' ? 'Maia3 Dart' : name;

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

  // Chess variant (game mode)
  ChessVariant get chessVariant {
    final name = _prefs?.getString(_keyChessVariant);
    if (name == null) return ChessVariant.standard;
    return ChessVariant.values.firstWhere(
      (v) => v.name == name,
      orElse: () => ChessVariant.standard,
    );
  }
  set chessVariant(ChessVariant v) => _prefs?.setString(_keyChessVariant, v.name);

  // Custom time control
  int get customBaseMinutes => _prefs?.getInt(_keyCustomBaseMinutes) ?? 10;
  set customBaseMinutes(int v) => _prefs?.setInt(_keyCustomBaseMinutes, v);

  int get customIncrementSeconds => _prefs?.getInt(_keyCustomIncrementSeconds) ?? 0;
  set customIncrementSeconds(int v) => _prefs?.setInt(_keyCustomIncrementSeconds, v);

  // Engine resource configuration
  int get engineHashMb => _prefs?.getInt(_keyEngineHashMb) ?? 64;
  set engineHashMb(int v) => _prefs?.setInt(_keyEngineHashMb, v);

  int get engineThreads => _prefs?.getInt(_keyEngineThreads) ?? 1;
  set engineThreads(int v) => _prefs?.setInt(_keyEngineThreads, v);

  // Board color theme
  String get boardTheme => _prefs?.getString(_keyBoardTheme) ?? 'brown';
  set boardTheme(String v) => _prefs?.setString(_keyBoardTheme, v);

  // Notation style
  String get notationStyle => _prefs?.getString(_keyNotationStyle) ?? 'algebraic';
  set notationStyle(String v) => _prefs?.setString(_keyNotationStyle, v);

  // Blindfold mode
  bool get blindfold => _prefs?.getBool(_keyBlindfold) ?? false;
  set blindfold(bool v) => _prefs?.setBool(_keyBlindfold, v);

  // Game state persistence
  static const _keyGameFen = 'gameFen';
  static const _keyGameMoves = 'gameMoves';

  String? get savedGameFen => _prefs?.getString(_keyGameFen);
  String? get savedGameMoves => _prefs?.getString(_keyGameMoves);

  void saveGame(String fen, List<String> moves) {
    _prefs?.setString(_keyGameFen, fen);
    _prefs?.setString(_keyGameMoves, moves.join(' '));
  }

  void clearSavedGame() {
    _prefs?.remove(_keyGameFen);
    _prefs?.remove(_keyGameMoves);
  }

  bool get hasSavedGame => _prefs?.containsKey(_keyGameFen) ?? false;

  // Game history
  static const _keyGameHistory = 'gameHistory';

  List<String> get gameHistory =>
      _prefs?.getStringList(_keyGameHistory) ?? [];

  void addGameToHistory(String pgn) {
    final history = gameHistory;
    history.insert(0, pgn);
    // Keep last 500 games
    if (history.length > 500) history.removeRange(500, history.length);
    _prefs?.setStringList(_keyGameHistory, history);
  }

  // Favorite games (stored as PGN strings that are starred)
  static const _keyFavoriteGames = 'favoriteGames';

  List<String> get favoriteGames =>
      _prefs?.getStringList(_keyFavoriteGames) ?? [];

  void toggleFavorite(String pgn) {
    final favs = favoriteGames;
    if (favs.contains(pgn)) {
      favs.remove(pgn);
    } else {
      favs.add(pgn);
    }
    _prefs?.setStringList(_keyFavoriteGames, favs);
  }

  bool isFavorite(String pgn) => favoriteGames.contains(pgn);

  // Bookmarks
  static const _keyBookmarks = 'bookmarks';

  List<String> get bookmarks =>
      _prefs?.getStringList(_keyBookmarks) ?? [];

  void addBookmark(String fen) {
    final bm = bookmarks;
    if (!bm.contains(fen)) {
      bm.insert(0, fen);
      if (bm.length > 100) bm.removeRange(100, bm.length);
      _prefs?.setStringList(_keyBookmarks, bm);
    }
  }

  void removeBookmark(String fen) {
    final bm = bookmarks;
    bm.remove(fen);
    _prefs?.setStringList(_keyBookmarks, bm);
  }

  // XP + streak
  static const _keyXp = 'totalXp';
  static const _keyLastLoginDate = 'lastLoginDate';
  static const _keyStreak = 'dailyStreak';

  int get totalXp => _prefs?.getInt(_keyXp) ?? 0;
  void addXp(int amount) =>
      _prefs?.setInt(_keyXp, totalXp + amount);

  int get dailyStreak => _prefs?.getInt(_keyStreak) ?? 0;

  /// Check daily login and update streak. Returns XP earned.
  int checkDailyLogin() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastLogin = _prefs?.getString(_keyLastLoginDate);

    if (lastLogin == today) return 0; // Already logged in today

    _prefs?.setString(_keyLastLoginDate, today);

    if (lastLogin != null) {
      final lastDate = DateTime.parse(lastLogin);
      final diff = DateTime.now().difference(lastDate).inDays;
      if (diff == 1) {
        // Consecutive day
        final newStreak = dailyStreak + 1;
        _prefs?.setInt(_keyStreak, newStreak);
        final xp = 5 + (newStreak.clamp(0, 10));
        addXp(xp);
        return xp;
      }
    }
    // Reset streak
    _prefs?.setInt(_keyStreak, 1);
    addXp(5);
    return 5;
  }

  // Mistakes tracker
  static const _keyMistakes = 'mistakes';

  List<String> get mistakes =>
      _prefs?.getStringList(_keyMistakes) ?? [];

  void addMistake(String mistakeJson) {
    final m = mistakes;
    m.insert(0, mistakeJson);
    if (m.length > 200) m.removeRange(200, m.length);
    _prefs?.setStringList(_keyMistakes, m);
  }

  void clearMistakes() => _prefs?.remove(_keyMistakes);

  // Spaced repetition queue
  static const _keySrQueue = 'sr_queue';

  List<String> get srQueue =>
      _prefs?.getStringList(_keySrQueue) ?? [];

  void saveSrQueue(List<String> items) =>
      _prefs?.setStringList(_keySrQueue, items);

  void addToSrQueue(String itemJson) {
    final q = srQueue;
    q.add(itemJson);
    if (q.length > 500) q.removeRange(0, q.length - 500);
    _prefs?.setStringList(_keySrQueue, q);
  }

  // Puzzle stats
  static const _keyPuzzlesSolved = 'puzzlesSolved';

  int get puzzlesSolved => _prefs?.getInt(_keyPuzzlesSolved) ?? 0;
  set puzzlesSolved(int v) => _prefs?.setInt(_keyPuzzlesSolved, v);

  // Games won
  static const _keyGamesWon = 'gamesWon';
  static const _keyGamesPlayed = 'gamesPlayed';

  int get gamesWon => _prefs?.getInt(_keyGamesWon) ?? 0;
  set gamesWon(int v) => _prefs?.setInt(_keyGamesWon, v);

  int get gamesPlayed => _prefs?.getInt(_keyGamesPlayed) ?? 0;
  set gamesPlayed(int v) => _prefs?.setInt(_keyGamesPlayed, v);

  /// Reset all preferences to defaults.
  Future<void> resetToDefaults() async {
    await _prefs?.clear();
  }
}
