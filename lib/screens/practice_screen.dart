import 'package:flutter/material.dart';
import '../chess/chess_game.dart';
import '../chess/spaced_repetition.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/practice_service.dart';
import '../services/preferences_service.dart';
import '../widgets/position_board.dart';
import 'ghost_practice_screen.dart';

class PracticeScreen extends StatefulWidget {
  final SrItem? initialItem;
  final bool dueOnly;
  const PracticeScreen({super.key, this.initialItem, this.dueOnly = true});
  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _prefs = PreferencesService();
  late final PracticeService _practice = PracticeService(_prefs);
  final _game = ChessGame();
  List<SrItem>? _queue;
  int _index = 0;
  bool _answered = false;
  bool _correct = false;
  bool _recorded = false;
  int _linePly = 0;
  String? _feedback;

  SrItem? get _item =>
      _queue != null && _index < _queue!.length ? _queue![_index] : null;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _prefs.init();
    if (!mounted) return;
    final initial = widget.initialItem;
    if (initial != null) _practice.add(initial);
    _queue = initial != null
        ? [initial]
        : widget.dueOnly
            ? getDueItems(_practice.items)
            : _practice.items;
    _reset();
  }

  void _reset() {
    final item = _item;
    if (item != null) _game.loadFen(item.fen);
    setState(() {
      _answered = false;
      _correct = false;
      _recorded = false;
      _linePly = 0;
      _feedback = null;
    });
  }

  void _record(bool correct) {
    if (_recorded) return;
    _practice.record(_item!, correct: correct);
    _recorded = true;
  }

  void _move(String uci) {
    if (_answered || _item == null) return;
    final l = AppLocalizations.of(context)!;
    final correct = uci == _item!.solution;
    _record(correct);
    if (correct) _game.makeMove(uci);
    setState(() {
      _correct = correct;
      _answered = correct;
      _feedback = correct ? l.practiceCorrect : l.practiceIncorrect;
      _linePly = correct ? 1 : 0;
    });
  }

  List<String> get _line {
    final item = _item!;
    return item.continuation.isNotEmpty &&
            item.continuation.first == item.solution
        ? item.continuation
        : [item.solution];
  }

  void _showLine(int count) {
    _game.loadFen(_item!.fen);
    for (final move in _line.take(count)) {
      if (!_game.makeMove(move)) break;
    }
    setState(() => _linePly = count);
  }

  String _lineSan() {
    final preview = ChessGame()..loadFen(_item!.fen);
    for (final move in _line) {
      if (!preview.makeMove(move)) break;
    }
    final san = preview.moveHistorySan.join(' ');
    preview.dispose();
    return san;
  }

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final item = _item;
    return Scaffold(
        appBar: AppBar(title: Text(l.practiceMistakes)),
        body: _queue == null
            ? const Center(child: CircularProgressIndicator())
            : item == null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_queue!.isEmpty
                            ? l.practiceEmpty
                            : l.practiceComplete)))
                : ListView(padding: const EdgeInsets.all(16), children: [
                    Text('${_index + 1} / ${_queue!.length}',
                        style: Theme.of(context).textTheme.labelLarge),
                    Text(l.findBestMove,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(item.fen.split(' ')[1] == 'w'
                        ? l.whiteToMoveLabel
                        : l.blackToMoveLabel),
                    const SizedBox(height: 12),
                    Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: PositionBoard(
                                key: ValueKey('${item.id}:$_answered'),
                                game: _game,
                                enabled: !_answered,
                                flipped: item.fen.split(' ')[1] == 'b',
                                onMove: _move))),
                    if (_feedback != null)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Semantics(
                              liveRegion: true,
                              child: Text(_feedback!,
                                  style: TextStyle(
                                      color: _correct
                                          ? Colors.green
                                          : Theme.of(context)
                                              .colorScheme
                                              .error)))),
                    if (!_answered)
                      TextButton(
                          onPressed: () {
                            _record(false);
                            setState(() => _answered = true);
                            _showLine(1);
                          },
                          child: Text(l.showSolutionAction)),
                    if (_answered) ...[
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.continuationAction),
                                    Text(_lineSan(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Row(children: [
                                      IconButton(
                                          tooltip:
                                              MaterialLocalizations.of(context)
                                                  .previousPageTooltip,
                                          onPressed: _linePly > 0
                                              ? () => _showLine(_linePly - 1)
                                              : null,
                                          icon: const Icon(Icons.chevron_left)),
                                      Text('$_linePly / ${_line.length}'),
                                      IconButton(
                                          tooltip:
                                              MaterialLocalizations.of(context)
                                                  .nextPageTooltip,
                                          onPressed: _linePly < _line.length
                                              ? () => _showLine(_linePly + 1)
                                              : null,
                                          icon:
                                              const Icon(Icons.chevron_right)),
                                    ]),
                                  ]))),
                      OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      GhostPracticeScreen(fen: item.fen))),
                          icon: const Icon(Icons.person_outline),
                          label: Text(l.playGhost)),
                      FilledButton(
                          onPressed: () {
                            _index++;
                            _reset();
                          },
                          child: Text(l.nextPosition)),
                    ],
                  ]));
  }
}
