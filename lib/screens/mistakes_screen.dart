import 'package:flutter/material.dart';
import '../chess/spaced_repetition.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/practice_service.dart';
import '../services/preferences_service.dart';
import 'practice_screen.dart';

/// The saved queue is the source of truth for both review and training.
class MistakesScreen extends StatefulWidget {
  const MistakesScreen({super.key});

  @override
  State<MistakesScreen> createState() => _MistakesScreenState();
}

class _MistakesScreenState extends State<MistakesScreen> {
  final _prefs = PreferencesService();
  List<SrItem>? _items;
  Future<void> _load() async {
    await _prefs.init();
    if (mounted) setState(() => _items = PracticeService(_prefs).items);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final due = getDueItems(_items ?? []).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.myMistakes),
        actions: [
          if (_items?.isNotEmpty ?? false)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l.clearMistakesAction,
              onPressed: () async {
                  final clear = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                              title: Text(l.clearMistakesAction),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(l.cancelAction)),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(l.clearAll)),
                              ]));
                  if (clear != true || !mounted) return;
                  _prefs.saveSrQueue([]);
                  _prefs.clearMistakes();
                  _load();
              }),
        ]),
      body: _items == null
            ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16),
                    children: [
                if (_items!.isEmpty) Text(l.practiceEmpty),
                if (due > 0)
                  FilledButton.icon(
                      icon: const Icon(Icons.school),
                      label: Text('${l.practiceMistakes} ($due)'),
                      onPressed: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const PracticeScreen()));
                        _load();
                      }),
                for (final item in _items!)
                  Card(
                      child: ListTile(
                        leading: Icon(item.isLearned
                        ? Icons.check_circle
                        : Icons.school_outlined),
                        title: Text(item.fen.split(' ')[1] == 'w'
                        ? l.whiteToMoveLabel
                        : l.blackToMoveLabel),
                        subtitle: Text('${item.correctAttempts}/${item.attempts} · '
                        '${MaterialLocalizations.of(context).formatShortDate(item.nextReview)}'),
                        trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  PracticeScreen(initialItem: item)));
                      _load();
                  },
                )),
              ]));
  }
}
