/// XP and player level system.

enum PlayerLevel {
  pawn('Pawn', 0),
  knight('Knight', 100),
  bishop('Bishop', 300),
  rook('Rook', 700),
  queen('Queen', 1500),
  grandmaster('Grandmaster', 3000);

  final String title;
  final int xpRequired;
  const PlayerLevel(this.title, this.xpRequired);
}

/// XP awards for different actions.
class XpAwards {
  static int gameWin(int difficulty) => 30 + (difficulty * 2);
  static const gameDraw = 15;
  static const gameLoss = 5; // participation
  static const puzzleSolve = 10;
  static const puzzleSolveFirst = 20; // first attempt
  static const dailyLogin = 5;
}

/// Get player level from total XP.
PlayerLevel levelFromXp(int xp) {
  for (final level in PlayerLevel.values.reversed) {
    if (xp >= level.xpRequired) return level;
  }
  return PlayerLevel.pawn;
}

/// XP needed for next level.
int xpForNextLevel(int xp) {
  final current = levelFromXp(xp);
  final idx = PlayerLevel.values.indexOf(current);
  if (idx >= PlayerLevel.values.length - 1) return 0; // Max level
  return PlayerLevel.values[idx + 1].xpRequired - xp;
}

/// Progress to next level (0.0 to 1.0).
double levelProgress(int xp) {
  final current = levelFromXp(xp);
  final idx = PlayerLevel.values.indexOf(current);
  if (idx >= PlayerLevel.values.length - 1) return 1.0;
  final next = PlayerLevel.values[idx + 1];
  final range = next.xpRequired - current.xpRequired;
  if (range <= 0) return 1.0;
  return (xp - current.xpRequired) / range;
}
