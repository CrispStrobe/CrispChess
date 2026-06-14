import 'package:flutter/material.dart';
import '../chess/chess_game.dart';
import '../chess/move_analyzer.dart';
import '../widgets/eval_chart.dart';

/// Post-game summary screen showing accuracy, eval chart, and key moments.
class GameSummaryScreen extends StatelessWidget {
  final List<String> movesSan;
  final List<double> evalHistory;
  final List<MoveAnnotation> annotations;
  final String gameResult;
  final String? winner;
  final String engineName;

  const GameSummaryScreen({
    super.key,
    required this.movesSan,
    required this.evalHistory,
    required this.annotations,
    required this.gameResult,
    this.winner,
    required this.engineName,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate accuracy
    final playerAnnotations = annotations.where((a) {
      // Even indices are player moves (0-indexed: 0, 2, 4...)
      final idx = annotations.indexOf(a);
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
            color: winner != null
                ? (winner == 'White' ? Colors.blue.shade50 : Colors.orange.shade50)
                : Colors.grey.shade100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(gameResult,
                      style: Theme.of(context).textTheme.headlineSmall),
                  if (winner != null) ...[
                    const SizedBox(height: 4),
                    Text('$winner wins',
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                  const SizedBox(height: 4),
                  Text('vs $engineName · ${movesSan.length} moves',
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
          if (evalHistory.length > 1)
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
                    EvalChart(evals: evalHistory, height: 80),
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

          // Move list
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Moves',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (int i = 0; i < movesSan.length; i++) ...[
                        if (i % 2 == 0)
                          Text('${i ~/ 2 + 1}.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                        Text(movesSan[i],
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: i % 2 == 0
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
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
