import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/chess_game.dart';
import '../chess/drill.dart';
import '../widgets/chess_board.dart';

/// Screen listing available drills.
class DrillListScreen extends StatelessWidget {
  const DrillListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = <String, List<Drill>>{};
    for (final drill in builtInDrills) {
      categories.putIfAbsent(drill.category, () => []).add(drill);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Drills')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in categories.entries) ...[
            Text(entry.key[0].toUpperCase() + entry.key.substring(1),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final drill in entry.value)
              Card(
                child: ListTile(
                  leading: Icon(_categoryIcon(drill.category), color: _categoryColor(drill.category)),
                  title: Text(drill.title),
                  subtitle: Text('${drill.steps.length} steps — ${drill.description}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => DrillPlayerScreen(drill: drill))),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  IconData _categoryIcon(String cat) => switch (cat) {
    'tactics' => Icons.flash_on,
    'endgame' => Icons.flag,
    'opening' => Icons.play_circle_outline,
    _ => Icons.school,
  };

  Color _categoryColor(String cat) => switch (cat) {
    'tactics' => Colors.red,
    'endgame' => Colors.blue,
    'opening' => Colors.green,
    _ => Colors.orange,
  };
}

/// Interactive drill player — shows positions and validates moves.
class DrillPlayerScreen extends StatefulWidget {
  final Drill drill;
  const DrillPlayerScreen({super.key, required this.drill});

  @override
  State<DrillPlayerScreen> createState() => _DrillPlayerScreenState();
}

class _DrillPlayerScreenState extends State<DrillPlayerScreen> {
  int _currentStep = 0;
  String _coachMessage = '';
  bool _stepComplete = false;
  int _attempts = 0;
  int _totalCorrectFirst = 0;
  late List<List<ChessPiece?>> _board;

  @override
  void initState() {
    super.initState();
    _loadStep();
  }

  void _loadStep() {
    final step = widget.drill.steps[_currentStep];
    _board = _parseBoardFromFen(step.fen);
    _coachMessage = step.hint ?? 'Find the best move.';
    _stepComplete = false;
    _attempts = 0;
  }

  DrillStep get _step => widget.drill.steps[_currentStep];

  bool get _whiteToMove => _step.fen.split(' ')[1] == 'w';

  void _onMove(int fromRow, int fromCol, int toRow, int toCol) {
    if (_stepComplete) return;

    final from = '${String.fromCharCode(97 + fromCol)}${8 - fromRow}';
    final to = '${String.fromCharCode(97 + toCol)}${8 - toRow}';
    final uci = '$from$to';
    _attempts++;

    if (uci == _step.correctMove) {
      // Correct!
      if (_attempts == 1) _totalCorrectFirst++;
      setState(() {
        _stepComplete = true;
        _coachMessage = _step.explanation ?? 'Correct!';
        // Update board to show the move played
        _board[toRow][toCol] = _board[fromRow][fromCol];
        _board[fromRow][fromCol] = null;
      });
    } else {
      // Wrong move
      final wrongMsg = _step.wrongMoveMessages[uci];
      setState(() {
        _coachMessage = wrongMsg ?? 'Not quite — try again!';
      });
    }
  }

  void _nextStep() {
    if (_currentStep < widget.drill.steps.length - 1) {
      setState(() {
        _currentStep++;
        _loadStep();
      });
    } else {
      // Drill complete
      _showSummary();
    }
  }

  void _showSummary() {
    final total = widget.drill.steps.length;
    final pct = total > 0 ? (_totalCorrectFirst / total * 100).round() : 0;

    // Save completion
    SharedPreferences.getInstance().then((prefs) {
      final key = 'drill_${widget.drill.id}';
      prefs.setBool(key, true);
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Drill Complete!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(pct >= 80 ? Icons.star : Icons.check_circle,
                size: 48, color: pct >= 80 ? Colors.amber : Colors.green),
            const SizedBox(height: 12),
            Text('$_totalCorrectFirst / $total correct on first try'),
            Text('Accuracy: $pct%', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = ((_currentStep + 1) / widget.drill.steps.length);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.drill.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress, minHeight: 4),
        ),
      ),
      body: Column(
        children: [
          // Step counter
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Step ${_currentStep + 1} of ${widget.drill.steps.length}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),

          // Board
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ChessBoard(
                  board: _board,
                  whiteToMove: _whiteToMove,
                  squareToAlgebraic: (r, c) => '${String.fromCharCode(97 + c)}${8 - r}',
                  onMove: _stepComplete ? null : _onMove,
                ),
              ),
            ),
          ),

          // Coach bubble
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _stepComplete
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _stepComplete ? Colors.green : Colors.blue,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _stepComplete ? Icons.check_circle : Icons.school,
                  color: _stepComplete ? Colors.green : Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_coachMessage, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),

          // Next button
          if (_stepComplete)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.icon(
                icon: Icon(_currentStep < widget.drill.steps.length - 1
                    ? Icons.arrow_forward
                    : Icons.check),
                label: Text(_currentStep < widget.drill.steps.length - 1
                    ? 'Next'
                    : 'Finish'),
                onPressed: _nextStep,
              ),
            ),
        ],
      ),
    );
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
}
