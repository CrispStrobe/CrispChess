import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chess/human_lens.dart';
import '../engines/uci_position.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/human_lens_service.dart';

/// SAN for a UCI move in [fen], or the UCI itself if it does not parse.
String sanForUci(String fen, String uci) {
  final board = chess_lib.Chess.fromFEN(fen);
  for (final m in board.generate_moves()) {
    final u =
        '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';
    if (u == uci) return board.move_to_san(m);
  }
  return uci;
}

String findabilityLabel(AppLocalizations? l, Findability f) => switch (f) {
      Findability.obvious => l?.findabilityObvious ?? 'Obvious',
      Findability.natural => l?.findabilityNatural ?? 'Natural',
      Findability.findable => l?.findabilityFindable ?? 'Findable',
      Findability.hard => l?.findabilityHard ?? 'Hard',
      Findability.veryHard => l?.findabilityVeryHard ?? 'Very hard',
    };

Color findabilityColor(Findability f) => switch (f) {
      Findability.obvious => Colors.green,
      Findability.natural => Colors.lightGreen.shade700,
      Findability.findable => Colors.amber.shade800,
      Findability.hard => Colors.deepOrange,
      Findability.veryHard => Colors.red.shade700,
    };

String _percent(double p) =>
    p >= 0.1 || p == 0 ? '${(p * 100).round()}' : (p * 100).toStringAsFixed(1);

/// Human Lens for the current position: what players of a chosen rating play
/// here, how findable the engine's move is, and whether the position is a trap.
class HumanLensSheet extends StatefulWidget {
  /// UCI `position` command of the position to look at.
  final String positionCommand;

  const HumanLensSheet({super.key, required this.positionCommand});

  @override
  State<HumanLensSheet> createState() => _HumanLensSheetState();
}

class _HumanLensSheetState extends State<HumanLensSheet> {
  static const _prefKey = 'humanLensElo';

  int _elo = 1400;
  HumanLensReport? _report;
  Object? _error;
  bool _busy = false;
  late final String _fen = fenFromPositionCommand(widget.positionCommand);
  late final bool _gameOver = chess_lib.Chess.fromFEN(_fen).game_over;
  late final bool _whiteToMove = _fen.split(' ')[1] != 'b';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getInt(_prefKey);
      if (saved != null && defaultEloLadder.contains(saved)) _elo = saved;
      if (!_gameOver) _run();
    });
  }

  Future<void> _run() async {
    final elo = _elo;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await HumanLensService.instance
          .analyzePosition(widget.positionCommand, elo: elo);
      if (!mounted || elo != _elo) return;
      setState(() => _report = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted && elo == _elo) setState(() => _busy = false);
    }
  }

  void _pickElo(int elo) {
    if (elo == _elo) return;
    setState(() {
      _elo = elo;
      _report = null;
    });
    SharedPreferences.getInstance().then((p) => p.setInt(_prefKey, elo));
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scroll) => Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.groups, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(l?.humanLens ?? 'Human Lens',
                  style: theme.textTheme.titleLarge),
            ]),
            const SizedBox(height: 4),
            Text(l?.humanLensSubtitle('$_elo') ??
                'How players rated $_elo see this position'),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in defaultEloLadder)
                ChoiceChip(
                  label: Text('$e'),
                  selected: e == _elo,
                  onSelected: (_) => _pickElo(e),
                ),
            ]),
            const SizedBox(height: 16),
            ..._body(l, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(AppLocalizations? l, ThemeData theme) {
    if (_gameOver) {
      return [Text(l?.humanLensGameOver ?? 'The game is over.')];
    }
    if (_error != null) {
      return [
        Text(l?.humanLensError('$_error') ?? 'Human Lens failed: $_error',
            style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _run, child: const Icon(Icons.refresh)),
      ];
    }
    final r = _report;
    if (r == null || _busy) {
      return [
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(HumanLensService.instance.isLoaded
            ? l?.humanLensThinking ?? 'Asking the players…'
            : l?.humanLensLoading ?? 'Loading Maia…'),
      ];
    }
    return [
      if (r.isTrap) _trapCard(l, r),
      if (r.bestMove != null) _bestMoveCard(l, theme, r),
      const SizedBox(height: 12),
      Text(l?.humanLensCandidates('${r.elo}') ?? 'What ${r.elo} players play',
          style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      for (final c in r.candidates) _candidateRow(theme, r, c),
    ];
  }

  Widget _trapCard(AppLocalizations? l, HumanLensReport r) {
    final trap = r.trapMove!;
    final san = sanForUci(_fen, trap.uci);
    return Card(
      color: Colors.red.withValues(alpha: 0.12),
      child: ListTile(
        leading: const Icon(Icons.warning_amber, color: Colors.red),
        title: Text(l?.humanLensTrap ?? 'Trap',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(l?.humanLensTrapText(
                _percent(trap.probability), '${r.elo}', san) ??
            '${_percent(trap.probability)}% of ${r.elo} players play $san, '
                'and it\'s a mistake.'),
      ),
    );
  }

  Widget _bestMoveCard(
      AppLocalizations? l, ThemeData theme, HumanLensReport r) {
    final san = sanForUci(_fen, r.bestMove!);
    final f = r.findability;
    final natural = r.naturalFromElo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(l?.humanLensBestMove ?? "Engine's move",
                  style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
              Text(san,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              _pill(findabilityLabel(l, f), findabilityColor(f)),
            ]),
            const SizedBox(height: 4),
            Text(l?.humanLensFoundBy(
                    _percent(r.bestMoveProbability), '${r.elo}') ??
                '${_percent(r.bestMoveProbability)}% of ${r.elo} players find it'),
            Text(
              natural != null
                  ? l?.humanLensNaturalFrom('$natural') ??
                      'Most players find it from about $natural'
                  : l?.humanLensNeverNatural ??
                      'Even at 2300 most players miss it',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(l?.humanLensByRating ?? "Who finds the engine's move",
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            _ladderChart(theme, r),
          ],
        ),
      ),
    );
  }

  /// One bar per rating: the share of those players who find the best move.
  Widget _ladderChart(ThemeData theme, HumanLensReport r) {
    const height = 64.0;
    return SizedBox(
      height: height + 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in r.findabilityByElo.entries)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${_percent(e.value)}%',
                        style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Container(
                      height: (height * e.value).clamp(2.0, height),
                      decoration: BoxDecoration(
                        color: e.key == r.elo
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('${e.key}', style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _candidateRow(ThemeData theme, HumanLensReport r, HumanCandidate c) {
    final isBest = c.uci == r.bestMove;
    // Shown from White's side, like every other evaluation in the app.
    final mover = c.evalAfter;
    final eval = mover == null ? null : (_whiteToMove ? mover : -mover);
    final color = isBest
        ? Colors.green
        : c.isMistake
            ? Colors.red
            : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 64,
          child: Row(children: [
            Text(sanForUci(_fen, c.uci),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (isBest) const Icon(Icons.star, size: 14, color: Colors.green),
            if (c.isMistake)
              const Icon(Icons.close, size: 14, color: Colors.red),
          ]),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: c.probability,
              minHeight: 10,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text('${_percent(c.probability)}%',
              textAlign: TextAlign.right),
        ),
        SizedBox(
          width: 52,
          child: Text(
            eval == null
                ? ''
                : '${eval >= 0 ? '+' : ''}${eval.toStringAsFixed(1)}',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      );
}
