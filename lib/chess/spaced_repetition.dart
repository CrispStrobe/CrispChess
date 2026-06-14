/// Spaced repetition system for re-presenting failed puzzles/mistakes.
///
/// Uses a simple interval schedule: 1 day, 3 days, 7 days, 14 days, 30 days.
/// Each time the user gets it wrong, reset to interval 0.
/// Each time they get it right, advance to the next interval.

import 'dart:convert';

const _intervals = [1, 3, 7, 14, 30]; // days

/// A single item in the spaced repetition queue.
class SrItem {
  final String fen;       // position FEN
  final String solution;  // correct move (UCI)
  final String description; // e.g. "Blunder: Qd1 instead of Nf3"
  int interval;            // current interval index (0-4)
  DateTime nextReview;     // when to show again
  int timesCorrect;        // streak of correct answers

  SrItem({
    required this.fen,
    required this.solution,
    required this.description,
    this.interval = 0,
    DateTime? nextReview,
    this.timesCorrect = 0,
  }) : nextReview = nextReview ?? DateTime.now();

  /// Is this item due for review?
  bool get isDue => DateTime.now().isAfter(nextReview);

  /// Mark as answered correctly — advance interval.
  void markCorrect() {
    timesCorrect++;
    if (interval < _intervals.length - 1) interval++;
    nextReview = DateTime.now().add(Duration(days: _intervals[interval]));
  }

  /// Mark as answered incorrectly — reset to beginning.
  void markIncorrect() {
    timesCorrect = 0;
    interval = 0;
    nextReview = DateTime.now().add(const Duration(days: 1));
  }

  /// Is this item "learned" (completed all intervals)?
  bool get isLearned => interval >= _intervals.length - 1 && timesCorrect > 0;

  Map<String, dynamic> toJson() => {
    'fen': fen,
    'solution': solution,
    'description': description,
    'interval': interval,
    'nextReview': nextReview.toIso8601String(),
    'timesCorrect': timesCorrect,
  };

  factory SrItem.fromJson(Map<String, dynamic> json) => SrItem(
    fen: json['fen'] as String,
    solution: json['solution'] as String,
    description: json['description'] as String? ?? '',
    interval: json['interval'] as int? ?? 0,
    nextReview: DateTime.tryParse(json['nextReview'] as String? ?? '') ?? DateTime.now(),
    timesCorrect: json['timesCorrect'] as int? ?? 0,
  );

  String encode() => jsonEncode(toJson());
  static SrItem decode(String s) => SrItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Get items that are due for review from a list.
List<SrItem> getDueItems(List<SrItem> items) {
  return items.where((item) => item.isDue && !item.isLearned).toList()
    ..sort((a, b) => a.nextReview.compareTo(b.nextReview));
}
