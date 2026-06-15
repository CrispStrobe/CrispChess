import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import '../chess/chess_game.dart';
import '../services/http_service.dart';
import '../widgets/chess_board.dart';

/// Opening Explorer — browse opening statistics from master games.
///
/// Uses the Lichess Explorer API (free, no auth required).
/// API: https://explorer.lichess.ovh/masters?fen=...
class OpeningExplorerScreen extends StatefulWidget {
  const OpeningExplorerScreen({super.key});

  @override
  State<OpeningExplorerScreen> createState() => _OpeningExplorerScreenState();
}

class _ExplorerMove {
  final String san;
  final String uci;
  final int white;
  final int draws;
  final int black;
  int get total => white + draws + black;
  double get whitePercent => total > 0 ? white / total * 100 : 0;
  double get drawPercent => total > 0 ? draws / total * 100 : 0;
  double get blackPercent => total > 0 ? black / total * 100 : 0;

  _ExplorerMove({
    required this.san,
    required this.uci,
    required this.white,
    required this.draws,
    required this.black,
  });
}

class _ExplorerData {
  final String? opening;
  final int white;
  final int draws;
  final int black;
  final List<_ExplorerMove> moves;
  int get total => white + draws + black;

  _ExplorerData({
    this.opening,
    required this.white,
    required this.draws,
    required this.black,
    required this.moves,
  });
}

class _OpeningExplorerScreenState extends State<OpeningExplorerScreen> {
  final chess.Chess _board = chess.Chess();
  final List<String> _moveHistory = []; // UCI moves played
  final List<String> _sanHistory = []; // SAN moves played
  _ExplorerData? _data;
  bool _loading = true;
  String _source = 'masters'; // 'masters' or 'lichess'
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final fen = Uri.encodeComponent(_board.fen);
    final url = _source == 'masters'
        ? 'https://explorer.lichess.ovh/masters?fen=$fen'
        : 'https://explorer.lichess.ovh/lichess?fen=$fen&ratings=1600,1800,2000,2200,2500&speeds=blitz,rapid,classical';

    final body = await httpGet(url);
    if (!mounted) return;

    if (body == null) {
      setState(() {
        _loading = false;
        _error = 'Failed to fetch data';
      });
      return;
    }

    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final moves = <_ExplorerMove>[];

      if (json['moves'] is List) {
        for (final m in json['moves'] as List) {
          moves.add(_ExplorerMove(
            san: m['san'] as String? ?? '?',
            uci: m['uci'] as String? ?? '',
            white: m['white'] as int? ?? 0,
            draws: m['draws'] as int? ?? 0,
            black: m['black'] as int? ?? 0,
          ));
        }
      }

      // Sort by total games descending
      moves.sort((a, b) => b.total.compareTo(a.total));

      setState(() {
        _data = _ExplorerData(
          opening: json['opening']?['name'] as String?,
          white: json['white'] as int? ?? 0,
          draws: json['draws'] as int? ?? 0,
          black: json['black'] as int? ?? 0,
          moves: moves,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Parse error: $e';
      });
    }
  }

  void _playMove(String uci, String san) {
    if (uci.length < 4) return;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = uci.length > 4 ? uci[4] : null;
    final move = <String, String>{'from': from, 'to': to};
    if (promo != null) move['promotion'] = promo;

    if (_board.move(move)) {
      _moveHistory.add(uci);
      _sanHistory.add(san);
      setState(() {});
      _fetchData();
    }
  }

  void _goBack() {
    if (_moveHistory.isEmpty) return;
    _board.undo();
    _moveHistory.removeLast();
    _sanHistory.removeLast();
    setState(() {});
    _fetchData();
  }

  void _reset() {
    _board.reset();
    _moveHistory.clear();
    _sanHistory.clear();
    setState(() {});
    _fetchData();
  }

  List<List<ChessPiece?>> get _boardState {
    final fen = _board.fen;
    final result = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    final ranks = fen.split(' ')[0].split('/');
    for (int rankIdx = 0; rankIdx < ranks.length; rankIdx++) {
      int colIdx = 0;
      for (final ch in ranks[rankIdx].split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          colIdx += n;
        } else {
          final color = ch == ch.toUpperCase() ? PieceColor.white : PieceColor.black;
          final type = switch (ch.toLowerCase()) {
            'p' => PieceType.pawn,
            'n' => PieceType.knight,
            'b' => PieceType.bishop,
            'r' => PieceType.rook,
            'q' => PieceType.queen,
            'k' => PieceType.king,
            _ => PieceType.pawn,
          };
          result[rankIdx][colIdx] = ChessPiece(type, color);
          colIdx++;
        }
      }
    }
    return result;
  }

  String _squareToAlgebraic(int row, int col) =>
      '${String.fromCharCode(97 + col)}${8 - row}';

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opening Explorer'),
        actions: [
          // Source toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'masters', label: Text('Masters', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 'lichess', label: Text('Online', style: TextStyle(fontSize: 11))),
            ],
            selected: {_source},
            onSelectionChanged: (v) {
              _source = v.first;
              _fetchData();
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Opening name + stats
          if (_data?.opening != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              width: double.infinity,
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Text(
                _data!.opening!,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),

          // Move history breadcrumbs
          if (_sanHistory.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              width: double.infinity,
              child: Wrap(
                spacing: 2,
                children: [
                  GestureDetector(
                    onTap: _reset,
                    child: Text('Start', style: TextStyle(fontSize: 11, color: Colors.blue.shade700, decoration: TextDecoration.underline)),
                  ),
                  for (int i = 0; i < _sanHistory.length; i++) ...[
                    Text(' > ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    Text(
                      '${i % 2 == 0 ? "${i ~/ 2 + 1}." : ""}${_sanHistory[i]}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == _sanHistory.length - 1 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Board
          Expanded(
            flex: 3,
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxHeight < constraints.maxWidth
                      ? constraints.maxHeight
                      : constraints.maxWidth;
                  return SizedBox(
                    width: size,
                    height: size,
                    child: ChessBoard(
                      board: _boardState,
                      whiteToMove: _board.turn == chess.Color.WHITE,
                      squareToAlgebraic: _squareToAlgebraic,
                    ),
                  );
                },
              ),
            ),
          ),

          // Navigation buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _moveHistory.isNotEmpty ? _reset : null,
                tooltip: 'Reset',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _moveHistory.isNotEmpty ? _goBack : null,
                tooltip: 'Back',
              ),
            ],
          ),

          // Move table
          Expanded(
            flex: 4,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade400)))
                    : _data == null || _data!.moves.isEmpty
                        ? Center(
                            child: Text(
                              'No data for this position',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : Column(
                            children: [
                              // Header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                color: Colors.grey.shade100,
                                child: Row(
                                  children: [
                                    const SizedBox(width: 48, child: Text('Move', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                    const SizedBox(width: 52, child: Text('Games', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                    const Expanded(child: Text('Result', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                    const SizedBox(width: 40, child: Text('White', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                                  ],
                                ),
                              ),
                              // Move list
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _data!.moves.length,
                                  itemBuilder: (context, index) {
                                    final m = _data!.moves[index];
                                    return InkWell(
                                      onTap: () => _playMove(m.uci, m.san),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 48,
                                              child: Text(m.san, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                            ),
                                            SizedBox(
                                              width: 52,
                                              child: Text(_formatNumber(m.total), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            ),
                                            // Win/Draw/Loss bar
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(3),
                                                child: SizedBox(
                                                  height: 14,
                                                  child: Row(
                                                    children: [
                                                      if (m.whitePercent > 0)
                                                        Flexible(
                                                          flex: m.white,
                                                          child: Container(color: Colors.white, child: Center(
                                                            child: m.whitePercent > 15 ? Text('${m.whitePercent.round()}%', style: const TextStyle(fontSize: 8, color: Colors.black54)) : null,
                                                          )),
                                                        ),
                                                      if (m.drawPercent > 0)
                                                        Flexible(
                                                          flex: m.draws,
                                                          child: Container(color: Colors.grey.shade400, child: Center(
                                                            child: m.drawPercent > 15 ? Text('${m.drawPercent.round()}%', style: const TextStyle(fontSize: 8, color: Colors.white)) : null,
                                                          )),
                                                        ),
                                                      if (m.blackPercent > 0)
                                                        Flexible(
                                                          flex: m.black,
                                                          child: Container(color: Colors.grey.shade800, child: Center(
                                                            child: m.blackPercent > 15 ? Text('${m.blackPercent.round()}%', style: const TextStyle(fontSize: 8, color: Colors.white)) : null,
                                                          )),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 40,
                                              child: Text(
                                                '${m.whitePercent.round()}%',
                                                style: const TextStyle(fontSize: 10),
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Total games footer
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                color: Colors.grey.shade50,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${_formatNumber(_data!.total)} games',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    if (_data!.total > 0) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        'W ${(_data!.white / _data!.total * 100).round()}% '
                                        'D ${(_data!.draws / _data!.total * 100).round()}% '
                                        'B ${(_data!.black / _data!.total * 100).round()}%',
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
