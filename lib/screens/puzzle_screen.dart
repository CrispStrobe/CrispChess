import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import '../chess/puzzle.dart';
import '../chess/chess_game.dart';
import '../widgets/chess_board.dart';
import 'puzzle_rush_screen.dart';

class PuzzleScreen extends StatefulWidget {
  final PuzzleDatabase puzzleDb;

  const PuzzleScreen({super.key, required this.puzzleDb});

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  ChessPuzzle? _puzzle;
  late chess.Chess _board;
  int _solutionIndex = 0;
  int _attempts = 0;
  bool _solved = false;
  bool _failed = false;
  String _message = '';
  int? _selectedRow, _selectedCol;
  List<String> _validMoves = [];
  int _solvedCount = 0;
  int _totalAttempted = 0;
  String _pieceTheme = 'chessnut';
  String _ratingFilter = 'all'; // 'all', '800-1200', '1200-1600', '1600-2000', '2000+'

  @override
  void initState() {
    super.initState();
    _loadNextPuzzle();
  }

  (int?, int?) get _ratingRange {
    return switch (_ratingFilter) {
      '800-1200' => (800, 1200),
      '1200-1600' => (1200, 1600),
      '1600-2000' => (1600, 2000),
      '2000+' => (2000, null),
      _ => (null, null),
    };
  }

  void _loadNextPuzzle() {
    final (minR, maxR) = _ratingRange;
    final puzzle = widget.puzzleDb.randomPuzzle(minRating: minR, maxRating: maxR);
    if (puzzle == null) {
      setState(() => _message = 'No puzzles available');
      return;
    }

    _puzzle = puzzle;
    _board = chess.Chess.fromFEN(puzzle.fen);

    // Apply the setup move (opponent's last move)
    if (puzzle.setupMove.isNotEmpty) {
      _applyUciMove(puzzle.setupMove);
    }

    setState(() {
      _solutionIndex = 0;
      _attempts = 0;
      _solved = false;
      _failed = false;
      _selectedRow = null;
      _selectedCol = null;
      _validMoves = [];
      _message = _board.turn == chess.Color.WHITE
          ? 'White to move'
          : 'Black to move';
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
      int file = 0;
      for (final ch in ranks[rankIdx].split('')) {
        final digit = int.tryParse(ch);
        if (digit != null) {
          file += digit;
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
          result[rankIdx][file] = ChessPiece(type, color);
          file++;
        }
      }
    }
    return result;
  }

  String _squareToAlgebraic(int row, int col) {
    return '${String.fromCharCode(97 + col)}${8 - row}';
  }

  PieceColor get _playerColor =>
      _board.turn == chess.Color.WHITE ? PieceColor.white : PieceColor.black;

  List<String> _getValidMovesForSquare(int row, int col) {
    final square = _squareToAlgebraic(row, col);
    return _board.moves({'verbose': true})
        .where((m) => m['from'] == square)
        .map((m) => '${m['from']}${m['to']}${m['promotion'] ?? ''}')
        .toList();
  }

  void _onSquareTap(int row, int col) {
    if (_solved || _failed) return;

    final board = _boardState;
    final piece = board[row][col];

    if (_selectedRow != null && _selectedCol != null) {
      if (_selectedRow == row && _selectedCol == col) {
        setState(() {
          _selectedRow = null;
          _selectedCol = null;
          _validMoves = [];
        });
        return;
      }

      if (piece != null && piece.color == _playerColor) {
        setState(() {
          _selectedRow = row;
          _selectedCol = col;
          _validMoves = _getValidMovesForSquare(row, col);
        });
        return;
      }

      final uci = _squareToAlgebraic(_selectedRow!, _selectedCol!) +
          _squareToAlgebraic(row, col);
      _tryMove(uci);
      setState(() {
        _selectedRow = null;
        _selectedCol = null;
        _validMoves = [];
      });
    } else if (piece != null && piece.color == _playerColor) {
      setState(() {
        _selectedRow = row;
        _selectedCol = col;
        _validMoves = _getValidMovesForSquare(row, col);
      });
    }
  }

  void _tryMove(String uci) {
    if (_puzzle == null || _solved || _failed) return;

    final solution = _puzzle!.solutionMoves;
    if (_solutionIndex >= solution.length) return;

    final expected = solution[_solutionIndex];

    // Check if the move matches (ignoring promotion for non-promo moves)
    final matches = uci == expected ||
        (uci.length == 4 && expected.startsWith(uci));

    if (matches) {
      _applyUciMove(expected);
      _solutionIndex++;

      if (_solutionIndex >= solution.length) {
        // Solved!
        setState(() {
          _solved = true;
          _solvedCount++;
          _message = 'Correct! Puzzle solved.';
        });
      } else {
        // Apply opponent's response
        final opponentMove = solution[_solutionIndex];
        _applyUciMove(opponentMove);
        _solutionIndex++;

        if (_solutionIndex >= solution.length) {
          setState(() {
            _solved = true;
            _solvedCount++;
            _message = 'Correct! Puzzle solved.';
          });
        } else {
          setState(() {
            _message = 'Correct! Find the next move.';
          });
        }
      }
    } else {
      _attempts++;
      if (_attempts >= 3) {
        setState(() {
          _failed = true;
          _message = 'Solution: ${solution.join(" ")}';
        });
      } else {
        setState(() {
          _message = 'Wrong move. Try again. (${3 - _attempts} left)';
        });
      }
    }
    _totalAttempted++;
  }

  void _showSolution() {
    if (_puzzle == null) return;
    setState(() {
      _failed = true;
      _message = 'Solution: ${_puzzle!.solutionMoves.join(" ")}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.extension, size: 20),
            const SizedBox(width: 8),
            const Text('Puzzles'),
            const Spacer(),
            Text('$_solvedCount solved',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PuzzleRushScreen(puzzleDb: widget.puzzleDb))),
            icon: const Icon(Icons.bolt, size: 18),
            label: const Text('Rush', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Rating filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: ['all', '800-1200', '1200-1600', '1600-2000', '2000+'].map((r) {
                final label = r == 'all' ? 'All' : r;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    selected: _ratingFilter == r,
                    visualDensity: VisualDensity.compact,
                    onSelected: (sel) {
                      if (sel) setState(() {
                        _ratingFilter = r;
                        _loadNextPuzzle();
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // Puzzle info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _solved
                ? Colors.green.shade50
                : _failed
                    ? Colors.red.shade50
                    : Colors.blue.shade50,
            child: Row(
              children: [
                Icon(
                  _solved
                      ? Icons.check_circle
                      : _failed
                          ? Icons.cancel
                          : Icons.lightbulb,
                  size: 20,
                  color: _solved
                      ? Colors.green
                      : _failed
                          ? Colors.red
                          : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_message,
                      style: const TextStyle(fontSize: 13)),
                ),
                if (_puzzle != null)
                  Chip(
                    label: Text('${_puzzle!.rating}',
                        style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
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
                      onSquareTap: _onSquareTap,
                      selectedRow: _selectedRow,
                      selectedCol: _selectedCol,
                      validMoves: _validMoves,
                      isCheck: _board.in_check,
                      pieceTheme: _pieceTheme,
                    ),
                  );
                },
              ),
            ),
          ),

          // Themes
          if (_puzzle != null && _puzzle!.themes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 4,
                children: _puzzle!.themes
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 10)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ),

          // Buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_solved && !_failed)
                  OutlinedButton.icon(
                    onPressed: _showSolution,
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Show Solution'),
                  ),
                if (_solved || _failed) ...[
                  FilledButton.icon(
                    onPressed: _loadNextPuzzle,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Next Puzzle'),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loadNextPuzzle,
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('Skip'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
