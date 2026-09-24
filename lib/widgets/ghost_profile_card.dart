import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chess/player_profile.dart';
import '../engines/ghost_engine.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/human_lens_service.dart';

/// What "Your Ghost" knows about you, and the button that measures the
/// rating it plays at.
class GhostProfileCard extends StatefulWidget {
  const GhostProfileCard({super.key});

  @override
  State<GhostProfileCard> createState() => _GhostProfileCardState();
}

class _GhostProfileCardState extends State<GhostProfileCard> {
  PlayerProfile? _profile;
  int? _elo;
  (int, int)? _progress;
  Object? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _profile = PlayerProfile.fromPgns(p.getStringList('gameHistory') ?? []);
        _elo = p.getInt(ghostEloKey);
      });
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _measure() async {
    final profile = _profile;
    if (profile == null || profile.moves.isEmpty) return;
    setState(() {
      _progress = (0, 1);
      _error = null;
    });
    try {
      final elo = await HumanLensService.instance.estimatePlayerElo(
        profile.moves,
        onProgress: (d, t) {
          if (mounted) setState(() => _progress = (d, t));
        },
        cancelled: () => _disposed,
      );
      if (elo != null) {
        final p = await SharedPreferences.getInstance();
        await p.setInt(ghostEloKey, elo);
        await p.setInt(ghostEloGamesKey, profile.games);
      }
      if (mounted) setState(() => _elo = elo ?? _elo);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = _profile;
    if (p == null) return const SizedBox.shrink();
    if (p.games == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(l?.ghostNoGames ??
              'Play a few games first: the Ghost learns from your game history.'),
        ),
      );
    }
    final fav = p.favouriteFirstMoves().take(3).map((e) => '${e.key} ×${e.value}');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l?.ghostGames('${p.games}', '${p.repertoire.length}') ??
                'Built from ${p.games} of your games, ${p.repertoire.length} opening positions'),
            if (fav.isNotEmpty)
              Text(l?.ghostFavourite(fav.join(', ')) ?? 'Your favourite first moves: ${fav.join(', ')}',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              _elo != null
                  ? l?.ghostRating('$_elo') ?? 'Plays like: $_elo'
                  : l?.ghostRatingUnmeasured ?? 'Rating not measured yet (plays like 1500)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_progress case (final done, final total))
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LinearProgressIndicator(value: total == 0 ? null : done / total),
                const SizedBox(height: 4),
                Text(l?.ghostMeasuring('$done', '$total') ?? 'Reading your moves… $done of $total',
                    style: theme.textTheme.bodySmall),
              ])
            else
              OutlinedButton.icon(
                onPressed: _measure,
                icon: const Icon(Icons.speed),
                label: Text(l?.ghostMeasure ?? 'Measure my rating'),
              ),
            if (_error != null)
              Text('$_error', style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
