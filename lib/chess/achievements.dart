/// Achievement system — tracks milestones and unlocks.

class Achievement {
  final String id;
  final String title;
  final String description;
  final String icon;
  final int target;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.target,
  });
}

const List<Achievement> allAchievements = [
  Achievement(id: 'first_win', title: 'First Victory', description: 'Win your first game', icon: '🏆', target: 1),
  Achievement(id: 'wins_5', title: 'Getting Stronger', description: 'Win 5 games', icon: '💪', target: 5),
  Achievement(id: 'wins_25', title: 'Veteran', description: 'Win 25 games', icon: '⭐', target: 25),
  Achievement(id: 'wins_100', title: 'Champion', description: 'Win 100 games', icon: '👑', target: 100),
  Achievement(id: 'games_10', title: 'Regular Player', description: 'Play 10 games', icon: '♟️', target: 10),
  Achievement(id: 'games_50', title: 'Dedicated', description: 'Play 50 games', icon: '🎯', target: 50),
  Achievement(id: 'puzzles_10', title: 'Puzzle Solver', description: 'Solve 10 puzzles', icon: '🧩', target: 10),
  Achievement(id: 'puzzles_50', title: 'Tactician', description: 'Solve 50 puzzles', icon: '🔥', target: 50),
  Achievement(id: 'level_knight', title: 'Knight Rank', description: 'Reach Knight level (100 XP)', icon: '♞', target: 100),
  Achievement(id: 'level_bishop', title: 'Bishop Rank', description: 'Reach Bishop level (300 XP)', icon: '♝', target: 300),
  Achievement(id: 'level_rook', title: 'Rook Rank', description: 'Reach Rook level (700 XP)', icon: '♜', target: 700),
  Achievement(id: 'level_queen', title: 'Queen Rank', description: 'Reach Queen level (1500 XP)', icon: '♛', target: 1500),
];

/// Check which achievements are unlocked based on current stats.
List<(Achievement, bool unlocked, double progress)> checkAchievements({
  required int gamesWon,
  required int gamesPlayed,
  required int puzzlesSolved,
  required int totalXp,
}) {
  return allAchievements.map((a) {
    final current = switch (a.id) {
      'first_win' || 'wins_5' || 'wins_25' || 'wins_100' => gamesWon,
      'games_10' || 'games_50' => gamesPlayed,
      'puzzles_10' || 'puzzles_50' => puzzlesSolved,
      'level_knight' || 'level_bishop' || 'level_rook' || 'level_queen' => totalXp,
      _ => 0,
    };
    final unlocked = current >= a.target;
    final progress = (current / a.target).clamp(0.0, 1.0);
    return (a, unlocked, progress);
  }).toList();
}
