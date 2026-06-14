import 'package:flutter/material.dart';

/// A drawn arrow on the board (from one square to another).
class BoardArrow {
  final String from; // algebraic, e.g. "e2"
  final String to;   // algebraic, e.g. "e4"
  final Color color;

  const BoardArrow({required this.from, required this.to, required this.color});

  @override
  bool operator ==(Object other) =>
      other is BoardArrow && from == other.from && to == other.to && color == other.color;

  @override
  int get hashCode => Object.hash(from, to, color);
}

/// A highlighted square on the board.
class BoardHighlight {
  final String square; // algebraic
  final Color color;

  const BoardHighlight({required this.square, required this.color});

  @override
  bool operator ==(Object other) =>
      other is BoardHighlight && square == other.square && color == other.color;

  @override
  int get hashCode => Object.hash(square, color);
}

/// Collection of board annotations (arrows + highlighted squares).
class BoardAnnotations {
  final List<BoardArrow> arrows = [];
  final List<BoardHighlight> highlights = [];

  void addArrow(BoardArrow arrow) {
    // Toggle: if same arrow exists, remove it
    final existing = arrows.indexWhere((a) => a.from == arrow.from && a.to == arrow.to);
    if (existing >= 0) {
      arrows.removeAt(existing);
    } else {
      arrows.add(arrow);
    }
  }

  void addHighlight(BoardHighlight highlight) {
    // Toggle: if same square exists with same color, remove it
    final existing = highlights.indexWhere(
        (h) => h.square == highlight.square && h.color == highlight.color);
    if (existing >= 0) {
      highlights.removeAt(existing);
    } else {
      // Remove any existing highlight on this square first
      highlights.removeWhere((h) => h.square == highlight.square);
      highlights.add(highlight);
    }
  }

  void clear() {
    arrows.clear();
    highlights.clear();
  }

  bool get isEmpty => arrows.isEmpty && highlights.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
