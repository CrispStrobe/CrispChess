import 'package:flutter/material.dart';
import '../chess/chess_game.dart';
import '../l10n/generated/app_localizations.dart';
import 'chess_board.dart';

/// Reusable legal move input for exercises and games started from a position.
class PositionBoard extends StatefulWidget {
  final ChessGame game;
  final bool enabled;
  final bool flipped;
  final String? hint;
  final ValueChanged<String> onMove;
  const PositionBoard(
      {super.key,
      required this.game,
      required this.onMove,
      this.enabled = true,
      this.flipped = false,
      this.hint});
  @override
  State<PositionBoard> createState() => _PositionBoardState();
}

class _PositionBoardState extends State<PositionBoard> {
  int? _row, _col;
  List<String> _moves = [];

  Future<void> _move(int fr, int fc, int tr, int tc) async {
    if (!widget.enabled) return;
    final prefix = widget.game.squareToAlgebraic(fr, fc) +
        widget.game.squareToAlgebraic(tr, tc);
    final moves =
        widget.game.getLegalMoves().where((m) => m.startsWith(prefix)).toList();
    if (moves.isEmpty) return;
    var move = moves.first;
    if (moves.length > 1) {
      final selected = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
                title: Text(AppLocalizations.of(ctx)!.promoteTo),
                children: [
                  for (final m in moves)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, m),
                        child: Text(m[4].toUpperCase()))
                ],
              ));
      if (!mounted || selected == null || !widget.enabled) return;
      move = selected;
    }
    setState(() {
      _row = null;
      _col = null;
      _moves = [];
    });
    widget.onMove(move);
  }

  void _tap(int row, int col) {
    if (!widget.enabled) return;
    if (_row != null &&
        _col != null &&
        _moves.any((m) =>
            m.substring(2, 4) == widget.game.squareToAlgebraic(row, col))) {
      _move(_row!, _col!, row, col);
      return;
    }
    setState(() {
      _row = row;
      _col = col;
      final from = widget.game.squareToAlgebraic(row, col);
      _moves =
          widget.game.getLegalMoves().where((m) => m.startsWith(from)).toList();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.game,
      builder: (context, _) => ChessBoard(
            board: widget.game.board,
            whiteToMove: widget.game.whiteToMove,
            squareToAlgebraic: widget.game.squareToAlgebraic,
            flipped: widget.flipped,
            onMove: widget.enabled ? _move : null,
            onSquareTap: widget.enabled ? _tap : null,
            selectedRow: _row,
            selectedCol: _col,
            validMoves: _moves,
            hintMove: widget.hint,
            isCheck: widget.game.inCheck,
            animationDurationMs: 0,
          ));
}
