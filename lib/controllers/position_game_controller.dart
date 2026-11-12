import 'package:flutter/foundation.dart';
import '../chess/chess_game.dart';
import '../engines/chess_engine.dart';
import '../engines/ghost_engine.dart';

/// Owns an isolated practice game and its opponent. No main-game state or
/// player statistics are touched; late engine answers cannot change a new game.
class PositionGameController extends ChangeNotifier {
  final ChessGame game = ChessGame();
  final ChessEngine engine;
  final bool playerIsWhite;
  bool loading = true;
  bool thinking = false;
  Object? error;
  bool _disposed = false;
  int _generation = 0;

  PositionGameController(String fen, {ChessEngine? engine})
      : engine = engine ?? GhostEngine(),
        playerIsWhite = fen.split(' ')[1] == 'w' {
    game.loadFen(fen);
  }

  bool get canMove =>
      !loading &&
      !thinking &&
      error == null &&
      !game.isGameOver &&
      game.whiteToMove == playerIsWhite;

  Future<void> initialize() async {
    if (_disposed) return;
    error = null;
    loading = true;
    notifyListeners();
    try {
      await engine.initialize();
      if (_disposed) {
        engine.dispose();
        return;
      }
      if (engine.state != EngineState.ready)
        throw StateError('Opponent unavailable');
    } catch (e) {
      if (!_disposed) error = e;
    }
    if (!_disposed) {
      loading = false;
      notifyListeners();
      if (error == null && game.whiteToMove != playerIsWhite) await reply();
    }
  }

  Future<void> move(String uci) async {
    if (!canMove || !game.makeMove(uci)) return;
    notifyListeners();
    if (!game.isGameOver) await reply();
  }

  Future<void> reply() async {
    if (_disposed ||
        thinking ||
        game.isGameOver ||
        game.whiteToMove == playerIsWhite) return;
    final generation = ++_generation;
    error = null;
    thinking = true;
    notifyListeners();
    try {
      final move = await engine.bestMove(game.positionCommand,
          moveTime: const Duration(milliseconds: 500));
      if (_disposed || generation != _generation) return;
      if (!game.makeMove(move))
        throw StateError('Opponent returned an illegal move');
    } catch (e) {
      if (!_disposed) error = e;
    }
    if (!_disposed) {
      thinking = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    engine.stop();
    engine.dispose();
    game.dispose();
    super.dispose();
  }
}
