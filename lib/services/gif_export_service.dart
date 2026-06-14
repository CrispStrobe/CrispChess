/// GIF export service — captures game positions as frames for animation.
///
/// Renders each move position to generate an animated replay.
/// Actual GIF encoding requires the `image` package — this module
/// provides the frame generation infrastructure.

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

/// A single frame in the animated game replay.
class GameFrame {
  final String fen;
  final String? moveSan;
  final int moveNumber;
  final Uint8List? pngBytes; // rendered PNG bytes

  GameFrame({
    required this.fen,
    this.moveSan,
    required this.moveNumber,
    this.pngBytes,
  });
}

/// Generate a list of FEN frames from a game's move history.
List<GameFrame> generateFrames(String startFen, List<String> movesFen) {
  final frames = <GameFrame>[
    GameFrame(fen: startFen, moveNumber: 0), // starting position
  ];

  for (int i = 0; i < movesFen.length; i++) {
    frames.add(GameFrame(
      fen: movesFen[i],
      moveNumber: i + 1,
    ));
  }

  return frames;
}

/// Capture a widget's render as PNG bytes.
Future<Uint8List?> captureWidget(RenderRepaintBoundary boundary, {double pixelRatio = 2.0}) async {
  try {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (e) {
    return null;
  }
}
