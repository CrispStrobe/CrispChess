import 'dart:async';
import '../l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import '../engines/chess_engine.dart';
import '../engines/engine_factory.dart';
import '../services/engine_match_service.dart';
import '../chess/chess_game.dart';
import '../widgets/chess_board.dart';

/// Screen for running engine vs engine matches.
class EngineMatchScreen extends StatefulWidget {
  const EngineMatchScreen({super.key});

  @override
  State<EngineMatchScreen> createState() => _EngineMatchScreenState();
}

class _EngineMatchScreenState extends State<EngineMatchScreen> {
  String _engine1Name = 'Built-in';
  String _engine2Name = 'Frozenight';
  int _numGames = 2;
  int _depth = 8;
  bool _running = false;
  bool _tournamentMode = false;
  EngineMatchService? _match;
  TournamentService? _tournament;
  StreamSubscription<MatchEvent>? _sub;

  /// Selected engines for tournament mode.
  final Set<String> _tournamentEngines = {'Built-in', 'Frozenight', 'Maia3 Dart'};

  final List<GameResult> _results = [];
  String _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  String _status = 'Configure and start';
  int _currentGame = 0;
  int _currentMoveCount = 0;

  static const _engineNames = ['Built-in', 'Frozenight', 'Stockfish', 'Maia3 Dart', 'Lc0'];

  @override
  void dispose() {
    _sub?.cancel();
    _match?.stop();
    _match?.dispose();
    _tournament?.stop();
    _tournament?.dispose();
    super.dispose();
  }

  Future<void> _startMatch() async {
    if (_engine1Name == _engine2Name) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select two different engines'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _running = true;
      _results.clear();
      _status = 'Initializing engines...';
    });

    final e1 = createEngine(_engine1Name);
    final e2 = createEngine(_engine2Name);

    _match = EngineMatchService(
      engine1: e1,
      engine2: e2,
      config: MatchConfig(numGames: _numGames, depthPerMove: _depth),
    );

    _sub = _match!.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case MatchGameStarted(:final gameNumber, :final white, :final black):
          setState(() {
            _currentGame = gameNumber;
            _currentMoveCount = 0;
            _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            _status = 'Game $gameNumber/$_numGames: $white vs $black';
          });
        case MatchMovePlayed(:final fen, :final move):
          setState(() {
            _currentFen = fen;
            _currentMoveCount++;
            _status = 'Game $_currentGame: move $_currentMoveCount ($move)';
          });
        case MatchGameFinished(:final result):
          setState(() {
            _results.add(result);
            _status = 'Game ${result.white} vs ${result.black}: ${result.result} (${result.moves} moves)';
          });
        case MatchFinished(:final results):
          final scores = EngineMatchService.scores(results);
          setState(() {
            _running = false;
            _status = 'Match complete! ${scores.entries.map((e) => '${e.key}: ${e.value}').join(' — ')}';
          });
        case TournamentRoundStart():
          break; // Handled in tournament mode
      }
    });

    await _match!.run();
  }

  Future<void> _startTournament() async {
    if (_tournamentEngines.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 3 engines'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _running = true;
      _results.clear();
      _status = 'Initializing tournament...';
    });

    final engines = _tournamentEngines.map((n) => createEngine(n)).toList();
    _tournament = TournamentService(engines: engines, depthPerMove: _depth);

    _sub = _tournament!.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case TournamentRoundStart(:final round, :final totalRounds, :final white, :final black):
          setState(() {
            _currentGame = round;
            _currentMoveCount = 0;
            _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            _status = 'Round $round/$totalRounds: $white vs $black';
          });
        case MatchMovePlayed(:final fen, :final move):
          setState(() {
            _currentFen = fen;
            _currentMoveCount++;
          });
        case MatchGameFinished(:final result):
          setState(() => _results.add(result));
        case MatchFinished(:final results):
          final standings = TournamentService.standings(results);
          setState(() {
            _running = false;
            _status = 'Tournament complete! Winner: ${standings.first.key}';
          });
        default:
          break;
      }
    });

    await _tournament!.run();
  }

  void _stopMatch() {
    _match?.stop();
    _tournament?.stop();
    setState(() {
      _running = false;
      _status = 'Stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scores = EngineMatchService.scores(_results);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engine vs Engine'),
        actions: [
          if (_running)
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.red),
              onPressed: _stopMatch,
            ),
        ],
      ),
      body: Column(
        children: [
          // Board display
          Expanded(
            flex: 3,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ChessBoard(
                  board: _parseBoardFromFen(_currentFen),
                  whiteToMove: _currentFen.contains(' w '),
                  squareToAlgebraic: _squareToAlgebraic,
                ),
              ),
            ),
          ),

          // Status
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),

          // Config (when not running)
          if (!_running) ...[
            // Mode toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Match'), icon: Icon(Icons.sports_esports, size: 16)),
                  ButtonSegment(value: true, label: Text('Tournament'), icon: Icon(Icons.emoji_events, size: 16)),
                ],
                selected: {_tournamentMode},
                onSelectionChanged: (s) => setState(() => _tournamentMode = s.first),
              ),
            ),

            if (!_tournamentMode) ...[
              // Match mode: select two engines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _engineDropdown('White', _engine1Name, (v) => setState(() => _engine1Name = v))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('vs')),
                    Expanded(child: _engineDropdown('Black', _engine2Name, (v) => setState(() => _engine2Name = v))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('Games: ', style: TextStyle(fontSize: 13)),
                    DropdownButton<int>(
                      value: _numGames,
                      underline: const SizedBox.shrink(),
                      items: [2, 4, 6, 10, 20].map((n) =>
                        DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                      onChanged: (v) => setState(() => _numGames = v!),
                    ),
                    const SizedBox(width: 16),
                    const Text('Depth: ', style: TextStyle(fontSize: 13)),
                    DropdownButton<int>(
                      value: _depth,
                      underline: const SizedBox.shrink(),
                      items: [4, 6, 8, 10, 12, 15].map((n) =>
                        DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                      onChanged: (v) => setState(() => _depth = v!),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Tournament mode: select 3+ engines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select engines (${_tournamentEngines.length} selected, min 3):',
                      style: const TextStyle(fontSize: 12)),
                    Wrap(
                      spacing: 6,
                      children: _engineNames.map((name) => FilterChip(
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        selected: _tournamentEngines.contains(name),
                        onSelected: (v) => setState(() {
                          if (v) _tournamentEngines.add(name);
                          else _tournamentEngines.remove(name);
                        }),
                      )).toList(),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Depth: ', style: TextStyle(fontSize: 13)),
                        DropdownButton<int>(
                          value: _depth,
                          underline: const SizedBox.shrink(),
                          items: [4, 6, 8, 10, 12].map((n) =>
                            DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                          onChanged: (v) => setState(() => _depth = v!),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],

          // Results table
          if (_results.isNotEmpty)
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // Score summary
                  if (scores.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: scores.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Chip(
                            label: Text('${e.key}: ${e.value}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        )).toList(),
                      ),
                    ),
                  // Game list
                  Expanded(
                    child: ListView.builder(
                      itemCount: _results.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final r = _results[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: r.result == '1-0' ? Colors.green
                                : r.result == '0-1' ? Colors.red : Colors.grey,
                            child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                          ),
                          title: Text('${r.white} vs ${r.black}', style: const TextStyle(fontSize: 12)),
                          subtitle: Text('${r.result} — ${r.moves} moves', style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: _running
          ? null
          : FloatingActionButton.extended(
              onPressed: _tournamentMode ? _startTournament : _startMatch,
              icon: const Icon(Icons.play_arrow),
              label: Text(_tournamentMode ? 'Start Tournament' : 'Start Match'),
            ),
    );
  }

  Widget _engineDropdown(String label, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: _engineNames.map((n) =>
            DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ],
    );
  }

  String _squareToAlgebraic(int row, int col) {
    return '${String.fromCharCode(97 + col)}${8 - row}';
  }

  List<List<ChessPiece?>> _parseBoardFromFen(String fen) {
    final result = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    final parts = fen.split(' ');
    final rows = parts[0].split('/');
    for (int r = 0; r < 8 && r < rows.length; r++) {
      int c = 0;
      for (var char in rows[r].split('')) {
        final empty = int.tryParse(char);
        if (empty != null) { c += empty; continue; }
        final color = char == char.toUpperCase() ? PieceColor.white : PieceColor.black;
        final type = _charToType(char.toLowerCase());
        if (c < 8) result[r][c] = ChessPiece(type, color);
        c++;
      }
    }
    return result;
  }

  PieceType _charToType(String c) {
    return switch (c) {
      'p' => PieceType.pawn, 'n' => PieceType.knight, 'b' => PieceType.bishop,
      'r' => PieceType.rook, 'q' => PieceType.queen, 'k' => PieceType.king,
      _ => PieceType.pawn,
    };
  }
}
