import 'package:flutter/material.dart';
import '../controllers/position_game_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../widgets/position_board.dart';

class GhostPracticeScreen extends StatefulWidget {
  final String fen;
  const GhostPracticeScreen({super.key, required this.fen});
  @override
  State<GhostPracticeScreen> createState() => _GhostPracticeScreenState();
}

class _GhostPracticeScreenState extends State<GhostPracticeScreen> {
  late final PositionGameController _controller;
  @override
  void initState() {
    super.initState();
    _controller = PositionGameController(widget.fen)..initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
        appBar: AppBar(title: Text(l.ghostPracticeTitle)),
        body: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final c = _controller;
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text(l.ghostPracticeNote),
                const SizedBox(height: 12),
                if (c.loading || c.thinking) const LinearProgressIndicator(),
                Text(c.loading
                    ? l.loadingOpponent
                    : c.thinking
                        ? l.ghostThinking
                        : c.game.isGameOver
                            ? c.game.gameOverReason
                            : c.game.whiteToMove
                                ? l.whiteToMoveLabel
                                : l.blackToMoveLabel),
                const SizedBox(height: 12),
                Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: PositionBoard(
                            game: c.game,
                            enabled: c.canMove,
                            flipped: !c.playerIsWhite,
                            onMove: c.move))),
                if (c.error != null) ...[
                  Text('${c.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  FilledButton(
                      onPressed: c.loading
                          ? null
                          : () {
                              if (c.engine.state.name != 'ready') {
                                c.initialize();
                              } else {
                                c.reply();
                              }
                            },
                      child: Text(l.retryAction)),
                ],
              ]);
            }));
  }
}
