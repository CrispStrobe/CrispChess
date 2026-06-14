import 'package:flutter/material.dart';
import '../chess/chess_game.dart';
import '../chess/game_tree.dart';
import '../chess/move_analyzer.dart';
import '../widgets/chess_board.dart';
import '../widgets/eval_chart.dart';

/// Post-game summary screen showing accuracy, eval chart, and key moments.
class GameSummaryScreen extends StatefulWidget {
  final List<String> movesSan;
  final List<double> evalHistory;
  final List<MoveAnnotation> annotations;
  final String gameResult;
  final String? winner;
  final String engineName;
  /// Game tree for interactive position replay.
  final GameTree? tree;

  const GameSummaryScreen({
    super.key,
    required this.movesSan,
    required this.evalHistory,
    required this.annotations,
    required this.gameResult,
    this.winner,
    required this.engineName,
    this.tree,
  });

  @override
  State<GameSummaryScreen> createState() => _GameSummaryScreenState();
}

class _GameSummaryScreenState extends State<GameSummaryScreen> {
  int _selectedMoveIndex = -1; // -1 = starting position
  List<List<ChessPiece?>>? _previewBoard;

  void _showPosition(int moveIndex) {
    if (widget.tree == null) return;
    final mainLine = widget.tree!.root.mainLine;
    if (moveIndex < 0 || moveIndex >= mainLine.length) {
      setState(() {
        _selectedMoveIndex = -1;
        _previewBoard = _parseBoardFromFen(widget.tree!.root.fen);
      });
      return;
    }
    final node = mainLine[moveIndex];
    setState(() {
      _selectedMoveIndex = moveIndex;
      _previewBoard = _parseBoardFromFen(node.fen);
    });
  }

  List<List<ChessPiece?>> _parseBoardFromFen(String fen) {
    final result = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    final rows = fen.split(' ')[0].split('/');
    for (int r = 0; r < 8 && r < rows.length; r++) {
      int c = 0;
      for (var ch in rows[r].split('')) {
        final empty = int.tryParse(ch);
        if (empty != null) { c += empty; continue; }
        final color = ch == ch.toUpperCase() ? PieceColor.white : PieceColor.black;
        final type = switch (ch.toLowerCase()) {
          'p' => PieceType.pawn, 'n' => PieceType.knight, 'b' => PieceType.bishop,
          'r' => PieceType.rook, 'q' => PieceType.queen, 'k' => PieceType.king,
          _ => PieceType.pawn,
        };
        if (c < 8) result[r][c] = ChessPiece(type, color);
        c++;
      }
    }
    return result;
  }

  String _squareToAlgebraic(int row, int col) =>
      '${String.fromCharCode(97 + col)}${8 - row}';

  @override
  Widget build(BuildContext context) {
    // Calculate accuracy
    final playerAnnotations = widget.annotations.where((a) {
      final idx = widget.annotations.indexOf(a);
      return idx % 2 == 0;
    }).toList();

    final totalMoves = playerAnnotations.length;
    int goodMoves = 0;
    int blunders = 0;
    int mistakes = 0;
    String? bestMoveStr;
    String? worstMoveStr;
    double worstLoss = 0;
    double bestGain = 0;

    for (final a in playerAnnotations) {
      final q = a.evaluation.quality;
      if (q == MoveQuality.brilliant || q == MoveQuality.good ||
          q == MoveQuality.neutral || q == MoveQuality.interesting) {
        goodMoves++;
      }
      if (q == MoveQuality.blunder) blunders++;
      if (q == MoveQuality.mistake) mistakes++;

      final loss = a.evaluation.centipawnLoss;
      if (loss > worstLoss) {
        worstLoss = loss;
        worstMoveStr = a.move;
      }
      final gain = -a.evaluation.evaluationChange;
      if (gain > bestGain) {
        bestGain = gain;
        bestMoveStr = a.move;
      }
    }

    final accuracy = totalMoves > 0
        ? (goodMoves / totalMoves * 100).round()
        : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Game Summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Result
          Card(
            color: widget.winner != null
                ? (widget.winner == 'White' ? Colors.blue.shade50 : Colors.orange.shade50)
                : Colors.grey.shade100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(widget.gameResult,
                      style: Theme.of(context).textTheme.headlineSmall),
                  if (widget.winner != null) ...[
                    const SizedBox(height: 4),
                    Text('${widget.winner} wins',
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                  const SizedBox(height: 4),
                  Text('vs ${widget.engineName} · ${widget.movesSan.length} moves',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Accuracy
          if (totalMoves > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, size: 20, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Text('Your Accuracy',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statBadge('$accuracy%', 'Accuracy',
                            accuracy >= 80 ? Colors.green : accuracy >= 50 ? Colors.orange : Colors.red),
                        _statBadge('$goodMoves', 'Good', Colors.green),
                        _statBadge('$mistakes', 'Mistakes', Colors.orange),
                        _statBadge('$blunders', 'Blunders', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Eval chart
          if (widget.evalHistory.length > 1)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.show_chart, size: 20, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Text('Evaluation',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    EvalChart(evals: widget.evalHistory, height: 80),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Best move
          if (bestMoveStr != null)
            Card(
              color: Colors.green.shade50,
              child: ListTile(
                leading: Icon(Icons.star, color: Colors.green.shade700),
                title: const Text('Your Best Move'),
                subtitle: Text(bestMoveStr,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text('+${bestGain.toStringAsFixed(1)}',
                    style: TextStyle(color: Colors.green.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ),

          // Worst move
          if (worstMoveStr != null && worstLoss > 0.3)
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: Icon(Icons.warning, color: Colors.red.shade700),
                title: const Text('Biggest Mistake'),
                subtitle: Text(worstMoveStr,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text('-${worstLoss.toStringAsFixed(1)}',
                    style: TextStyle(color: Colors.red.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ),

          const SizedBox(height: 12),

          // Interactive board preview (shown when a move is tapped)
          if (_previewBoard != null && widget.tree != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 20),
                          onPressed: () => _showPosition(-1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          onPressed: _selectedMoveIndex > 0
                              ? () => _showPosition(_selectedMoveIndex - 1)
                              : null,
                        ),
                        Text('Move ${_selectedMoveIndex + 1}',
                            style: const TextStyle(fontSize: 12)),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 20),
                          onPressed: _selectedMoveIndex < widget.movesSan.length - 1
                              ? () => _showPosition(_selectedMoveIndex + 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 20),
                          onPressed: () => _showPosition(widget.movesSan.length - 1),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 200,
                      child: ChessBoard(
                        board: _previewBoard!,
                        whiteToMove: true,
                        squareToAlgebraic: _squareToAlgebraic,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Move list (clickable)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Moves',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      if (widget.tree != null) ...[
                        const Spacer(),
                        Text('Tap to view position',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (int i = 0; i < widget.movesSan.length; i++) ...[
                        if (i % 2 == 0)
                          Text('${i ~/ 2 + 1}.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                        GestureDetector(
                          onTap: widget.tree != null ? () => _showPosition(i) : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                            decoration: i == _selectedMoveIndex
                                ? BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: Colors.blue, width: 1),
                                  )
                                : null,
                            child: Text(widget.movesSan[i],
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: i == _selectedMoveIndex || i % 2 == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: i == _selectedMoveIndex ? Colors.blue : null,
                                )),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statBadge(String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}
