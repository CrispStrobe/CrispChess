import 'dart:math';
import 'package:flutter/material.dart';

/// Compact evaluation chart showing the eval trajectory across the game.
///
/// White advantage is green (above midline), black advantage is red (below).
/// Each dot represents a half-move's evaluation.
class EvalChart extends StatelessWidget {
  /// Evaluations in centipawns for each half-move.
  final List<double> evals;

  /// Height of the chart.
  final double height;

  const EvalChart({
    super.key,
    required this.evals,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    if (evals.isEmpty) return SizedBox(height: height);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          size: Size(double.infinity, height),
          painter: _EvalChartPainter(evals),
        ),
      ),
    );
  }
}

class _EvalChartPainter extends CustomPainter {
  final List<double> evals;

  _EvalChartPainter(this.evals);

  @override
  void paint(Canvas canvas, Size size) {
    if (evals.isEmpty) return;

    final midY = size.height / 2;
    final maxEval = 6.0; // Clamp at ±6 pawns

    // Draw midline
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = Colors.grey.shade400
        ..strokeWidth = 0.5,
    );

    // Draw eval areas
    final whiteFill = Paint()..color = Colors.green.withValues(alpha: 0.3);
    final blackFill = Paint()..color = Colors.red.withValues(alpha: 0.3);
    final linePaint = Paint()
      ..color = Colors.blue.shade700
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()..style = PaintingStyle.fill;

    final path = Path();
    final whitePath = Path();
    final blackPath = Path();

    whitePath.moveTo(0, midY);
    blackPath.moveTo(0, midY);

    for (int i = 0; i < evals.length; i++) {
      final x = evals.length == 1
          ? size.width / 2
          : i * size.width / (evals.length - 1);
      final clamped = evals[i].clamp(-maxEval, maxEval);
      final y = midY - (clamped / maxEval) * midY;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      // Fill areas
      if (clamped >= 0) {
        whitePath.lineTo(x, y);
        blackPath.lineTo(x, midY);
      } else {
        whitePath.lineTo(x, midY);
        blackPath.lineTo(x, y);
      }
    }

    whitePath.lineTo(size.width, midY);
    whitePath.close();
    blackPath.lineTo(size.width, midY);
    blackPath.close();

    canvas.drawPath(whitePath, whiteFill);
    canvas.drawPath(blackPath, blackFill);
    canvas.drawPath(path, linePaint);

    // Draw dots
    for (int i = 0; i < evals.length; i++) {
      final x = evals.length == 1
          ? size.width / 2
          : i * size.width / (evals.length - 1);
      final clamped = evals[i].clamp(-maxEval, maxEval);
      final y = midY - (clamped / maxEval) * midY;

      dotPaint.color = clamped >= 0 ? Colors.green.shade700 : Colors.red.shade700;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_EvalChartPainter old) => evals != old.evals;
}
