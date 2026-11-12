import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/drill.dart';
import '../chess/puzzle.dart';
import '../chess/spaced_repetition.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/daily_practice_service.dart';
import '../services/practice_service.dart';
import '../services/preferences_service.dart';
import 'drill_screen.dart';
import 'mistakes_screen.dart';
import 'practice_screen.dart';
import 'puzzle_screen.dart';
import 'stats_screen.dart';

class TrainingHubScreen extends StatefulWidget {
  const TrainingHubScreen({super.key});
  @override
  State<TrainingHubScreen> createState() => _TrainingHubScreenState();
}

class _TrainingHubScreenState extends State<TrainingHubScreen> {
  final _prefs = PreferencesService();
  DailyPracticeService? _daily;
  List<SrItem> _items = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _prefs.init();
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() {
        _daily = DailyPracticeService(prefs);
        _items = PracticeService(_prefs).items;
      });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final due = getDueItems(_items).length;
    final reviewTarget = (due + (_daily?.count('review') ?? 0)).clamp(0, 3);
    final attempts = _items.fold<int>(0, (n, i) => n + i.attempts);
    final correct = _items.fold<int>(0, (n, i) => n + i.correctAttempts);
    Widget goal(
        String title, String activity, int target, VoidCallback action) {
      final count = _daily?.count(activity) ?? 0;
      return ListTile(
          leading: Icon(
              count >= target ? Icons.check_circle : Icons.circle_outlined),
          title: Text(title),
          subtitle: LinearProgressIndicator(
              value: target == 0 ? 1 : (count / target).clamp(0, 1)),
          trailing: Text('${count.clamp(0, target)}/$target'),
          onTap: action);
    }

    return Scaffold(
        appBar: AppBar(title: Text(l.trainTab)),
        body: _daily == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Text(l.dailyPractice,
                    style: Theme.of(context).textTheme.headlineSmall),
                Card(
                    child: Column(children: [
                  goal('${l.practiceMistakes} ($due)', 'review', reviewTarget,
                      () => _open(const PracticeScreen())),
                  goal(l.puzzlePractice, 'puzzle', 5, () async {
                    final db = PuzzleDatabase();
                    await db.load();
                    if (mounted) _open(PuzzleScreen(puzzleDb: db));
                  }),
                  goal(
                      l.endgamePractice,
                      'endgame',
                      1,
                      () => _open(DrillPlayerScreen(
                          drill: builtInDrills
                              .firstWhere((d) => d.category == 'endgame')))),
                ])),
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.trending_up),
                        title: Text(l.practiceProgress),
                        subtitle: Text(
                            '${l.accuracy}: ${attempts == 0 ? '—' : '${(100 * correct / attempts).round()}%'} · '
                            '${l.practicePositions}: ${_items.length} · ✓ ${_items.where((i) => i.isLearned).length}'))),
                ListTile(
                    leading: const Icon(Icons.library_books),
                    title: Text(l.practiceAll),
                    onTap: () => _open(const PracticeScreen(dueOnly: false))),
                ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text(l.myMistakes),
                    onTap: () => _open(const MistakesScreen())),
                ListTile(
                    leading: const Icon(Icons.school),
                    title: Text(l.drills),
                    onTap: () => _open(const DrillListScreen())),
                ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: Text(l.statsAndAchievements),
                    onTap: () => _open(const StatsScreen())),
              ]));
  }
}
