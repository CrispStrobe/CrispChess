/// Chess puzzle data model and loader.
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

class ChessPuzzle {
  final String fen;
  final List<String> moves; // First move is opponent's (setup), rest are solution
  final List<String> themes;
  final int rating;

  const ChessPuzzle({
    required this.fen,
    required this.moves,
    required this.themes,
    required this.rating,
  });

  /// The position FEN after the opponent's setup move.
  /// This is what the player sees when solving.
  String get puzzleFen => fen;

  /// The opponent's last move (first in the list) — shown as context.
  String get setupMove => moves.isNotEmpty ? moves[0] : '';

  /// The solution moves the player must find (all moves after the setup).
  List<String> get solutionMoves => moves.length > 1 ? moves.sublist(1) : [];

  /// The first move the player must make.
  String get firstSolutionMove =>
      solutionMoves.isNotEmpty ? solutionMoves[0] : '';

  factory ChessPuzzle.fromJson(Map<String, dynamic> json) {
    return ChessPuzzle(
      fen: json['fen'] as String,
      moves: (json['moves'] as String).split(' '),
      themes: (json['themes'] as List?)?.cast<String>() ??
          (json['themes'] as String?)?.split(' ') ??
          [],
      rating: json['rating'] as int? ?? 1500,
    );
  }
}

class PuzzleDatabase {
  List<ChessPuzzle> _puzzles = [];

  bool get isLoaded => _puzzles.isNotEmpty;
  int get count => _puzzles.length;

  Future<void> load() async {
    if (_puzzles.isNotEmpty) return;
    try {
      final json = await rootBundle.loadString('assets/puzzles.json');
      final list = jsonDecode(json) as List;
      _puzzles = list.map((e) => ChessPuzzle.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      _puzzles = [];
    }
  }

  /// Get a random puzzle, optionally filtered by theme or rating range.
  ChessPuzzle? randomPuzzle({String? theme, int? minRating, int? maxRating}) {
    var pool = _puzzles;
    if (theme != null) {
      pool = pool.where((p) => p.themes.contains(theme)).toList();
    }
    if (minRating != null) {
      pool = pool.where((p) => p.rating >= minRating).toList();
    }
    if (maxRating != null) {
      pool = pool.where((p) => p.rating <= maxRating).toList();
    }
    if (pool.isEmpty) return null;
    return pool[Random().nextInt(pool.length)];
  }

  /// Get all available themes.
  Set<String> get themes {
    final t = <String>{};
    for (final p in _puzzles) {
      t.addAll(p.themes);
    }
    return t;
  }

  /// Get puzzles by theme.
  List<ChessPuzzle> byTheme(String theme) {
    return _puzzles.where((p) => p.themes.contains(theme)).toList();
  }

  /// Get daily puzzle (deterministic by date).
  ChessPuzzle? dailyPuzzle() {
    if (_puzzles.isEmpty) return null;
    final day = DateTime.now().difference(DateTime(2026, 1, 1)).inDays;
    return _puzzles[day % _puzzles.length];
  }
}
