import 'dart:math';
import 'package:flutter/material.dart';

/// Animated particle burst effect shown on a capture square.
class CaptureEffect extends StatefulWidget {
  /// Board-relative position (0-7 for row and col).
  final int row;
  final int col;
  final double squareSize;
  final bool flipped;
  final VoidCallback onComplete;

  const CaptureEffect({
    super.key,
    required this.row,
    required this.col,
    required this.squareSize,
    required this.onComplete,
    this.flipped = false,
  });

  @override
  State<CaptureEffect> createState() => _CaptureEffectState();
}

class _CaptureEffectState extends State<CaptureEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _controller.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vCol = widget.flipped ? 7 - widget.col : widget.col;
    final vRow = widget.flipped ? 7 - widget.row : widget.row;
    final left = vCol * widget.squareSize;
    final top = vRow * widget.squareSize;

    return Positioned(
      left: left,
      top: top,
      width: widget.squareSize,
      height: widget.squareSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ParticlePainter(
              progress: _controller.value,
              size: widget.squareSize,
            ),
          );
        },
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double progress;
  final double size;
  static final _rng = Random(42); // fixed seed for consistent pattern
  static final _particles = List.generate(12, (i) {
    final angle = (i / 12) * 2 * pi + _rng.nextDouble() * 0.5;
    final speed = 0.6 + _rng.nextDouble() * 0.4;
    return (angle, speed);
  });

  _ParticlePainter({required this.progress, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(size / 2, size / 2);
    final maxRadius = size * 0.6;

    // Ring burst
    final ringPaint = Paint()
      ..color = Colors.orange.withValues(alpha: (1 - progress) * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * (1 - progress);
    canvas.drawCircle(center, maxRadius * progress, ringPaint);

    // Particles
    for (final (angle, speed) in _particles) {
      final dist = maxRadius * progress * speed;
      final x = center.dx + cos(angle) * dist;
      final y = center.dy + sin(angle) * dist;
      final particleSize = size * 0.04 * (1 - progress);

      final paint = Paint()
        ..color = Colors.orange.withValues(alpha: (1 - progress) * 0.8);
      canvas.drawCircle(Offset(x, y), particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
