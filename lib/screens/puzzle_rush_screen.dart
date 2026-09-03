import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/puzzle.dart';
import '../chess/chess_game.dart';
import '../widgets/chess_board.dart';

/// Puzzle Rush — solve as many puzzles as possible before time or lives run out.
class PuzzleRushScreen extends StatefulWidget {
  final PuzzleDatabase puzzleDb;
  final int durationSeconds;

  const PuzzleRushScreen({
    super.key,
    required this.puzzleDb,
    this.durationSeconds = 180, // 3 minutes default
  });

  @override
  State<PuzzleRushScreen> createState() => _PuzzleRushScreenState();
}

class _PuzzleRushScreenState extends State<PuzzleRushScreen> {
  late chess.Chess _board;
  ChessPuzzle? _puzzle;
  int _solutionIndex = 0;
  int _score = 0;
  int _lives = 3;
  int _secondsLeft = 0;
  bool _running = false;
  String _message = '';
  int? _selectedRow, _selectedCol;
  List<String> _validMoves = [];
  int _bestScore = 0;
  Timer? _timer;
  String _pieceTheme = 'chessnut';

  @override
  void initState() {
    super.initState();
    _board = chess.Chess();
    _secondsLeft = widget.durationSeconds;
    _loadBest();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _bestScore = prefs.getInt('puzzleRushBest') ?? 0);
    }
    // Auto-start
    _startRush();
  }

  Future<void> _saveBest() async {
    if (_score > _bestScore) {
      _bestScore = _score;
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt('puzzleRushBest', _bestScore);
    }
  }

  void _startRush() {
    setState(() {
      _score = 0;
      _lives = 3;
      _secondsLeft = widget.durationSeconds;
      _running = true;
    });
    _loadNextPuzzle();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _endRush();
      }
    });
  }

  void _endRush() {
    _timer?.cancel();
    setState(() {
      _running = false;
    });
    _saveBest();
    _showResults();
  }

  void _loadNextPuzzle() {
    final puzzle = widget.puzzleDb.randomPuzzle();
    if (puzzle == null) return;

    _puzzle = puzzle;
    _board = chess.Chess.fromFEN(puzzle.fen);

    // Apply setup move
    if (puzzle.setupMove.isNotEmpty) {
      _applyUciMove(puzzle.setupMove);
    }

    setState(() {
      _solutionIndex = 0;
      _selectedRow = null;
      _selectedCol = null;
      _validMoves = [];
      _message = _board.turn == chess.Color.WHITE ? 'White to move' : 'Black to move';
    });
  }

  bool _applyUciMove(String uci) {
    if (uci.length < 4) return false;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = uci.length > 4 ? uci[4] : null;
    final move = <String, String>{'from': from, 'to': to};
    if (promo != null) move['promotion'] = promo;
    return _board.move(move);
  }

  List<List<ChessPiece?>> get _boardState {
    final fen = _board.fen;
    final result = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    final parts = fen.split(' ');
    final ranks = parts[0].split('/');
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

  String _squareToAlgebraic(int row, int col) {
    return '${String.fromCharCode(97 + col)}${8 - row}';
  }

  void _onSquareTap(int row, int col) {
    if (!_running || _puzzle == null) return;

    final square = _squareToAlgebraic(row, col);
    final piece = _board.get(square);

    if (_selectedRow != null && _selectedCol != null) {
      final from = _squareToAlgebraic(_selectedRow!, _selectedCol!);
      final to = square;
      _tryMove(from, to);
    } else if (piece != null && piece.color == _board.turn) {
      final moves = _board.generate_moves()
          .where((m) => m.fromAlgebraic == square)
          .map((m) => m.toAlgebraic)
          .toList();
      setState(() {
        _selectedRow = row;
        _selectedCol = col;
        _validMoves = moves;
      });
    }
  }

  void _onMove(int fromRow, int fromCol, int toRow, int toCol) {
    if (!_running) return;
    final from = _squareToAlgebraic(fromRow, fromCol);
    final to = _squareToAlgebraic(toRow, toCol);
    _tryMove(from, to);
  }

  void _tryMove(String from, String to) {
    if (_puzzle == null) return;
    final solution = _puzzle!.solutionMoves;
    if (_solutionIndex >= solution.length) return;

    final expectedUci = solution[_solutionIndex];
    final expectedFrom = expectedUci.substring(0, 2);
    final expectedTo = expectedUci.substring(2, 4);

    if (from == expectedFrom && to.startsWith(expectedTo.substring(0, 2))) {
      // Correct move
      _applyUciMove(expectedUci);
      _solutionIndex++;

      if (_solutionIndex >= solution.length) {
        // Puzzle solved!
        setState(() {
          _score++;
          _message = 'Correct! +1';
          _selectedRow = null;
          _selectedCol = null;
          _validMoves = [];
        });
        // Brief delay then load next puzzle
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _running) _loadNextPuzzle();
        });
      } else {
        // Apply opponent's response
        if (_solutionIndex < solution.length) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!mounted || !_running) return;
            _applyUciMove(solution[_solutionIndex]);
            _solutionIndex++;
            setState(() {
              _selectedRow = null;
              _selectedCol = null;
              _validMoves = [];
              _message = _board.turn == chess.Color.WHITE ? 'White to move' : 'Black to move';
            });
          });
        }
        setState(() {
          _selectedRow = null;
          _selectedCol = null;
          _validMoves = [];
        });
      }
    } else {
      // Wrong move — lose a life
      setState(() {
        _lives--;
        _message = 'Wrong! Lives: $_lives';
        _selectedRow = null;
        _selectedCol = null;
        _validMoves = [];
      });
      if (_lives <= 0) {
        _endRush();
      } else {
        // Skip to next puzzle
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _running) _loadNextPuzzle();
        });
      }
    }
  }

  void _showResults() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(_lives <= 0 ? 'No lives left!' : 'Time\'s up!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_score', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
            const Text('puzzles solved'),
            const SizedBox(height: 12),
            Text('Best: $_bestScore', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Exit'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startRush();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    final timeStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt, size: 20),
            const SizedBox(width: 8),
            const Text('Puzzle Rush'),
            const Spacer(),
            // Lives
            Row(
              children: List.generate(3, (i) => Icon(
                i < _lives ? Icons.favorite : Icons.favorite_border,
                color: i < _lives ? Colors.red : Colors.grey,
                size: 18,
              )),
            ),
            const SizedBox(width: 12),
            // Timer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _secondsLeft <= 10 ? Colors.red.shade100 : Colors.blue.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                timeStr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _secondsLeft <= 10 ? Colors.red : Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Score + puzzle info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Text('Score: $_score',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_message, style: const TextStyle(fontSize: 13)),
                if (_puzzle != null) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text('${_puzzle!.rating}', style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
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
                  return SizedBox(
                    width: size,
                    height: size,
                    child: ChessBoard(
                      board: _boardState,
                      whiteToMove: _board.turn == chess.Color.WHITE,
                      squareToAlgebraic: _squareToAlgebraic,
                      onSquareTap: _running ? _onSquareTap : null,
                      onMove: _running ? _onMove : null,
                      selectedRow: _selectedRow,
                      selectedCol: _selectedCol,
                      validMoves: _validMoves,
                      isCheck: _board.in_check,
                      pieceTheme: _pieceTheme,
                      flipped: _board.turn == chess.Color.BLACK,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
