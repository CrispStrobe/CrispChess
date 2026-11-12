import '../chess/chess_game.dart';
import '../chess/game_tree.dart';
import '../chess/xp_system.dart';
import '../services/preferences_service.dart';

class GameCompletion {
  final PlayerLevel levelBefore;
  final PlayerLevel levelAfter;
  final bool playerWon;
  const GameCompletion(this.levelBefore, this.levelAfter, this.playerWon);
}

/// Persistence and completion accounting, separate from dialogs and widgets.
class GameSessionController {
  final PreferencesService prefs;
  GameTree? _completedTree;
  GameSessionController(this.prefs);

  void save(ChessGame game) {
    if (game.hasMoves && !game.isGameOver) {
      prefs.saveGame(game.currentFEN, game.moveHistory,
          startFen: game.tree.root.fen);
    } else {
      prefs.clearSavedGame();
    }
  }

  List<String> restore(ChessGame game) {
    final moves =
        prefs.savedGameMoves?.split(' ').where((m) => m.isNotEmpty).toList() ??
            [];
    final start = prefs.savedGameStartFen;
    if (start != null) {
      if (!game.loadFen(start)) return [];
    } else {
      game.reset();
    }
    final applied = <String>[];
    for (final move in moves) {
      if (!game.makeMove(move)) break;
      applied.add(move);
    }
    return applied;
  }

  GameCompletion? finish(ChessGame game,
      {required String engineName,
      required bool playAsBlack,
      required bool twoPlayer,
      required int strengthLevel}) {
    if (identical(_completedTree, game.tree)) return null;
    _completedTree = game.tree;
    final before = levelFromXp(prefs.totalXp);
    final won = game.winner == (playAsBlack ? 'Black' : 'White');
    prefs.gamesPlayed++;
    // A pass-and-play win does not measure the selected AI opponent's strength.
    if (!twoPlayer) {
      if (won) {
        prefs.gamesWon++;
        prefs.addXp(XpAwards.gameWin(strengthLevel));
      } else {
        prefs
            .addXp(game.winner == null ? XpAwards.gameDraw : XpAwards.gameLoss);
      }
    }
    prefs.addGameToHistory(game.toPgn(
        engineName: twoPlayer ? 'Human' : engineName,
        playAsBlack: playAsBlack));
    prefs.clearSavedGame();
    return GameCompletion(
        before, levelFromXp(prefs.totalXp), won && !twoPlayer);
  }
}
