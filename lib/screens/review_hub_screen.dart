import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../chess/chess_game.dart';
import '../chess/pgn.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/preferences_service.dart';
import 'game_history_screen.dart';
import 'game_summary_screen.dart';
import 'mistakes_screen.dart';

class ReviewHubScreen extends StatefulWidget {
  const ReviewHubScreen({super.key});
  @override
  State<ReviewHubScreen> createState() => _ReviewHubScreenState();
}

class _ReviewHubScreenState extends State<ReviewHubScreen> {
  final _prefs = PreferencesService();
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _prefs.init();
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _review(String pgn) async {
    final game = ChessGame();
    if (!game.loadPgn(pgn)) {
      game.dispose();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.invalidReviewPgn)));
      return;
    }
    final headers = parseHeaders(pgn);
    final l = AppLocalizations.of(context)!;
    final white = await showDialog<bool>(
        context: context,
        builder: (ctx) => SimpleDialog(title: Text(l.reviewSide), children: [
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('${l.white} · ${headers['White'] ?? ''}')),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('${l.black} · ${headers['Black'] ?? ''}')),
            ]));
    if (!mounted || white == null) {
      game.dispose();
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GameSummaryScreen(
                movesSan: game.moveHistorySan,
                evalHistory: const [],
                annotations: const [],
                gameResult: headers['Result'] ?? '*',
                engineName: headers[white ? 'Black' : 'White'] ?? '',
                tree: game.tree,
                positionCommand: game.positionCommand,
                playerIsWhite: white)));
    game.dispose();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
        appBar: AppBar(title: Text(l.reviewTab)),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Text(l.recentGames,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    icon: const Icon(Icons.paste),
                    label: Text(l.pastePgn),
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (mounted && data?.text != null) _review(data!.text!);
                    }),
                OutlinedButton.icon(
                    icon: const Icon(Icons.history),
                    label: Text(l.gameHistory),
                    onPressed: () async {
                      final pgn = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const GameHistoryScreen()));
                      if (mounted && pgn != null) _review(pgn);
                    }),
                OutlinedButton.icon(
                    icon: const Icon(Icons.school),
                    label: Text(l.practiceMistakes),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MistakesScreen()))),
                for (final pgn in _prefs.gameHistory.take(10))
                  Builder(builder: (context) {
                    final h = parseHeaders(pgn);
                    return Card(
                        child: ListTile(
                            leading: const Icon(Icons.analytics_outlined),
                            title: Text(
                                '${h['White'] ?? '?'} — ${h['Black'] ?? '?'}'),
                            subtitle: Text(
                                '${h['Date'] ?? ''} · ${h['Result'] ?? '*'}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _review(pgn)));
                  }),
                if (_prefs.gameHistory.isEmpty) Text(l.reviewPending),
              ]));
  }
}
