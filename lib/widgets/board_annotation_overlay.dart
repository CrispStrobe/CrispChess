import 'dart:math';
import 'package:flutter/material.dart';
import '../chess/board_annotations.dart';

/// Paints arrows and square highlights over the chess board.
class BoardAnnotationOverlay extends StatelessWidget {
  final BoardAnnotations annotations;
  final double boardSize;
  final bool flipped;

  const BoardAnnotationOverlay({
    super.key,
    required this.annotations,
    required this.boardSize,
    this.flipped = false,
  });

  @override
  Widget build(BuildContext context) {
    if (annotations.isEmpty) return const SizedBox.shrink();

    return CustomPaint(
      size: Size(boardSize, boardSize),
      painter: _AnnotationPainter(
        annotations: annotations,
        flipped: flipped,
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final BoardAnnotations annotations;
  final bool flipped;

  _AnnotationPainter({required this.annotations, required this.flipped});

  @override
  void paint(Canvas canvas, Size size) {
    final squareSize = size.width / 8;

    // Draw highlighted squares first (behind arrows)
    for (final h in annotations.highlights) {
      final (col, row) = _parseSquare(h.square);
      if (col < 0) continue;
      final vCol = flipped ? 7 - col : col;
      final vRow = flipped ? 7 - row : row;

      final paint = Paint()
        ..color = h.color.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(vCol * squareSize, vRow * squareSize, squareSize, squareSize),
        paint,
      );
    }

    // Draw arrows
    for (final arrow in annotations.arrows) {
      final (fromCol, fromRow) = _parseSquare(arrow.from);
      final (toCol, toRow) = _parseSquare(arrow.to);
      if (fromCol < 0 || toCol < 0) continue;

      final vFromCol = flipped ? 7 - fromCol : fromCol;
      final vFromRow = flipped ? 7 - fromRow : fromRow;
      final vToCol = flipped ? 7 - toCol : toCol;
      final vToRow = flipped ? 7 - toRow : toRow;

      final from = Offset(
        (vFromCol + 0.5) * squareSize,
        (vFromRow + 0.5) * squareSize,
      );
      final to = Offset(
        (vToCol + 0.5) * squareSize,
        (vToRow + 0.5) * squareSize,
      );

      _drawArrow(canvas, from, to, arrow.color, squareSize);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color, double squareSize) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final length = sqrt(dx * dx + dy * dy);
    if (length < 1) return;

    final unitX = dx / length;
    final unitY = dy / length;

    // Arrowhead size
    final headLen = squareSize * 0.35;
    final headWidth = squareSize * 0.25;
    final shaftWidth = squareSize * 0.12;

    // Shorten arrow so head doesn't overshoot
    final shaftEnd = Offset(
      to.dx - unitX * headLen,
      to.dy - unitY * headLen,
    );

    // Perpendicular direction
    final perpX = -unitY;
    final perpY = unitX;

    // Draw shaft
    final shaftPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = shaftWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, shaftEnd, shaftPaint);

    // Draw arrowhead
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(shaftEnd.dx + perpX * headWidth, shaftEnd.dy + perpY * headWidth)
      ..lineTo(shaftEnd.dx - perpX * headWidth, shaftEnd.dy - perpY * headWidth)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// Parse algebraic square to (col, row) where a1 = (0, 7).
  (int, int) _parseSquare(String sq) {
    if (sq.length < 2) return (-1, -1);
    final col = sq.codeUnitAt(0) - 97; // 'a' = 0
    final row = 8 - int.parse(sq[1]);   // '1' = row 7, '8' = row 0
    if (col < 0 || col > 7 || row < 0 || row > 7) return (-1, -1);
    return (col, row);
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) => true;
}
