import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Coordinate Trainer — learn square names by tapping the correct square.
class CoordinateTrainerScreen extends StatefulWidget {
  const CoordinateTrainerScreen({super.key});

  @override
  State<CoordinateTrainerScreen> createState() => _CoordinateTrainerScreenState();
}

class _CoordinateTrainerScreenState extends State<CoordinateTrainerScreen> {
  final _rng = Random();
  int _targetCol = 0; // 0-7 = a-h
  int _targetRow = 0; // 0-7 = 1-8
  int _score = 0;
  int _mistakes = 0;
  int _bestScore = 0;
  bool _timedMode = false;
  bool _running = false;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadBestScore();
    _generateTarget();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _bestScore = prefs.getInt('coordTrainerBest') ?? 0);
    }
  }

  Future<void> _saveBestScore() async {
    if (_score > _bestScore) {
      _bestScore = _score;
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt('coordTrainerBest', _bestScore);
    }
  }

  void _generateTarget() {
    setState(() {
      _targetCol = _rng.nextInt(8);
      _targetRow = _rng.nextInt(8);
    });
  }

  String get _targetName {
    final file = String.fromCharCode(97 + _targetCol); // a-h
    final rank = (_targetRow + 1).toString(); // 1-8
    return '$file$rank';
  }

  void _startTimedMode() {
    setState(() {
      _timedMode = true;
      _running = true;
      _score = 0;
      _mistakes = 0;
      _secondsLeft = 30;
    });
    _generateTarget();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        setState(() => _running = false);
        _saveBestScore();
        _showResults();
      }
    });
  }

  void _showResults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Time\'s up!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Score: $_score',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Mistakes: $_mistakes', style: TextStyle(color: Colors.grey.shade600)),
            Text('Best: $_bestScore', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startTimedMode();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  void _onSquareTap(int col, int row) {
    // row: 0=rank 8 (top), 7=rank 1 (bottom) in visual order
    // Our target uses: row 0=rank 1 (bottom), 7=rank 8 (top)
    // Visual row 0 = rank 8 → targetRow 7
    // Visual row 7 = rank 1 → targetRow 0
    final tappedRow = 7 - row; // Convert visual row to rank-based row
    if (tappedRow == _targetRow && col == _targetCol) {
      setState(() => _score++);
      _generateTarget();
    } else {
      setState(() => _mistakes++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.grid_on, size: 20),
            const SizedBox(width: 8),
            const Text('Coordinate Trainer'),
            const Spacer(),
            if (_timedMode && _running)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _secondsLeft <= 5 ? Colors.red.shade100 : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_secondsLeft}s',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _secondsLeft <= 5 ? Colors.red : Colors.blue,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Score bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Score: $_score', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Mistakes: $_mistakes', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                Text('Best: $_bestScore', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),

          // Target square name
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _targetName,
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
          ),

          // Board
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxHeight < constraints.maxWidth
                      ? constraints.maxHeight
                      : constraints.maxWidth;
                  final boardSize = size * 0.95;
                  final squareSize = boardSize / 8;

                  return SizedBox(
                    width: boardSize,
                    height: boardSize,
                    child: Column(
                      children: List.generate(8, (visualRow) {
                        return Expanded(
                          child: Row(
                            children: List.generate(8, (col) {
                              final isLight = (visualRow + col) % 2 == 0;
                              // Highlight target square
                              final dataRow = 7 - visualRow;
                              final isTarget = dataRow == _targetRow && col == _targetCol;

                              return Expanded(
                                child: GestureDetector(
                                  onTap: (!_timedMode || _running) ? () => _onSquareTap(col, visualRow) : null,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isLight
                                          ? const Color(0xFFEEEED2)
                                          : const Color(0xFF769656),
                                    ),
                                    child: Center(
                                      child: (visualRow == 7)
                                          ? Align(
                                              alignment: Alignment.bottomCenter,
                                              child: Text(
                                                String.fromCharCode(97 + col),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: isLight
                                                      ? const Color(0xFF769656)
                                                      : const Color(0xFFEEEED2),
                                                ),
                                              ),
                                            )
                                          : (col == 0)
                                              ? Align(
                                                  alignment: Alignment.topLeft,
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(left: 2, top: 1),
                                                    child: Text(
                                                      '${8 - visualRow}',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: isLight
                                                            ? const Color(0xFF769656)
                                                            : const Color(0xFFEEEED2),
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : null,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_timedMode || !_running)
                  FilledButton.icon(
                    onPressed: _startTimedMode,
                    icon: const Icon(Icons.timer, size: 18),
                    label: Text(_timedMode ? 'Play Again (30s)' : 'Timed Mode (30s)'),
                  ),
                if (!_timedMode) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _score = 0;
                        _mistakes = 0;
                      });
                      _generateTarget();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
