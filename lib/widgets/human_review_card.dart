import 'package:flutter/material.dart';

import '../chess/human_lens.dart';
import '../engines/uci_position.dart';
import '../l10n/generated/app_localizations.dart';
import '../screens/human_lens_sheet.dart' show findabilityColor, sanForUci;
import '../services/human_lens_service.dart';

/// Post-game "human review": the player's costly misses, split into ones that
/// were genuinely hard to find and plain slips, plus the rating their moves
/// looked like. Runs on demand — it is a model pass per move per rating.
class HumanReviewCard extends StatefulWidget {
  /// UCI `position` command of the final position (carries every move).
  final String positionCommand;

  /// Which side's moves to review.
  final bool playerIsWhite;

  /// Called with a ply when a miss is tapped, to show that position.
  final void Function(int ply)? onShowPly;

  const HumanReviewCard({
    super.key,
    required this.positionCommand,
    required this.playerIsWhite,
    this.onShowPly,
  });

  @override
  State<HumanReviewCard> createState() => _HumanReviewCardState();
}

class _HumanReviewCardState extends State<HumanReviewCard> {
  int _elo = 1500;
  List<HumanMoveReview>? _reviews;
  (int, int)? _progress;
  Object? _error;
  bool _running = false;
  bool _disposed = false;

  late final ({String baseFen, List<String> moves}) _parsed =
      parsePositionCommand(widget.positionCommand);

  /// Plies of the player's moves. The base position may have Black to move.
  late final List<int> _plies = () {
    final whiteFirst = _parsed.baseFen.split(' ')[1] != 'b';
    final playerFirst = whiteFirst == widget.playerIsWhite;
    return [
      for (var p = playerFirst ? 0 : 1; p < _parsed.moves.length; p += 2) p
    ];
  }();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
      _reviews = null;
      _progress = (0, _plies.length);
    });
    try {
      final r = await HumanLensService.instance.reviewGame(
        widget.positionCommand,
        plies: _plies,
        elo: _elo,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done, total));
        },
        cancelled: () => _disposed,
      );
      if (mounted) setState(() => _reviews = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// FEN before [ply], for SAN.
  String _fenBefore(int ply) => fenFromPositionCommand(ply == 0
      ? 'position fen ${_parsed.baseFen}'
      : 'position fen ${_parsed.baseFen} moves '
          '${_parsed.moves.take(ply).join(' ')}');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.groups, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(l?.humanReview ?? 'Human review',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            ..._content(l, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(AppLocalizations? l, ThemeData theme) {
    if (_plies.isEmpty) return const [];
    if (_running) {
      final (done, total) = _progress ?? (0, _plies.length);
      return [
        LinearProgressIndicator(value: total == 0 ? null : done / total),
        const SizedBox(height: 6),
        Text(done == 0 && !HumanLensService.instance.isLoaded
            ? l?.humanLensLoading ?? 'Loading Maia…'
            : l?.humanReviewProgress('$done', '$total') ??
                'Move $done of $total…'),
      ];
    }
    final reviews = _reviews;
    if (reviews == null) {
      return [
        Text(l?.humanReviewIntro ??
            'See the game the way Maia sees human players.'),
        const SizedBox(height: 12),
        Text(l?.humanReviewRatingLabel ?? 'Compare with players rated',
            style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [
          for (final e in HumanLensService.reviewLadder)
            ChoiceChip(
              label: Text('$e'),
              selected: e == _elo,
              onSelected: (_) => setState(() => _elo = e),
            ),
        ]),
        const SizedBox(height: 8),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                l?.humanLensError('$_error') ?? 'Human Lens failed: $_error',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: Text(l?.humanReviewStart ?? 'Review with Maia'),
        ),
      ];
    }

    final estimate = estimateElo(reviews);
    final misses = reviews.where((r) => r.isMistake && !r.playedBest).toList();
    return [
      if (estimate != null)
        Text(
          l?.humanReviewPlayedLike('$estimate') ??
              'Your moves looked like a player rated about $estimate',
          style: theme.textTheme.titleMedium,
        ),
      const SizedBox(height: 8),
      if (misses.isEmpty)
        Text(l?.humanReviewNoMistakes ?? 'No costly misses in this game.'),
      for (final m in misses) _missTile(l, m),
    ];
  }

  Widget _missTile(AppLocalizations? l, HumanMoveReview m) {
    final fen = _fenBefore(m.ply);
    final played = sanForUci(fen, m.played);
    final best = sanForUci(fen, m.bestMove!);
    final f = m.missedFindability!;
    // Hard to find: fewer than one in ten at this rating would have played it.
    final hard = m.bestProbability < 0.1;
    final moveNo = '${m.ply ~/ 2 + 1}${m.ply.isEven ? '.' : '...'}';
    final percent = (m.bestProbability * 100).round();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: widget.onShowPly == null ? null : () => widget.onShowPly!(m.ply),
      leading: Icon(hard ? Icons.visibility_off : Icons.error_outline,
          color: findabilityColor(f)),
      title: Text(
          '$moveNo ${l?.humanReviewMissText(played, best, '$percent', '$_elo') ?? '$played instead of $best: $percent% of $_elo players find it'}'),
      trailing: Text(
        hard
            ? l?.humanReviewHardMiss ?? 'Hard to find'
            : l?.humanReviewSlip ?? 'Slip',
        style: TextStyle(
            color: findabilityColor(f), fontWeight: FontWeight.bold),
      ),
    );
  }
}
