import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../chess/achievements.dart';
import '../chess/xp_system.dart';
import '../services/preferences_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _prefs = PreferencesService();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _prefs.init().then((_) => setState(() => _loaded = true));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(l?.stats ?? 'Stats')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final xp = _prefs.totalXp;
    final level = levelFromXp(xp);
    final progress = levelProgress(xp);
    final nextXp = xpForNextLevel(xp);

    final achievements = checkAchievements(
      gamesWon: _prefs.gamesWon,
      gamesPlayed: _prefs.gamesPlayed,
      puzzlesSolved: _prefs.puzzlesSolved,
      totalXp: xp,
    );
    final unlocked = achievements.where((a) => a.$2).length;

    return Scaffold(
      appBar: AppBar(title: Text(l?.statsAndAchievements ?? 'Stats & Achievements')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Level card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(level.title,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text('$xp XP${nextXp > 0 ? ' · $nextXp to next level' : ' · Max level!'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Stats
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('${_prefs.gamesPlayed}', l?.games ?? 'Games'),
                  _stat('${_prefs.gamesWon}', l?.wins ?? 'Wins'),
                  _stat('${_prefs.puzzlesSolved}', l?.puzzles ?? 'Puzzles'),
                  _stat('$unlocked/${allAchievements.length}', l?.badges ?? 'Badges'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text(l?.achievements ?? 'Achievements', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          // Achievement list
          ...achievements.map((entry) {
            final (achievement, isUnlocked, prog) = entry;
            return Card(
              color: isUnlocked ? Colors.green.shade50 : null,
              child: ListTile(
                leading: Text(achievement.icon, style: TextStyle(
                    fontSize: 24,
                    color: isUnlocked ? null : Colors.grey)),
                title: Text(achievement.title,
                    style: TextStyle(
                        fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
                        color: isUnlocked ? null : Colors.grey)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(achievement.description,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: prog,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      color: isUnlocked ? Colors.green : null,
                    ),
                  ],
                ),
                trailing: isUnlocked
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : Text('${(prog * 100).round()}%',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ),
            );
          }),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}
