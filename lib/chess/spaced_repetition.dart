import 'dart:convert';

const _intervals = [1, 3, 7, 14, 30];

/// A position collected from a verified review or a Human Lens miss.
class SrItem {
  final String fen;
  final String solution;
  final String description;
  final List<String> continuation;
  final String source;
  int interval;
  DateTime nextReview;
  int timesCorrect;
  int attempts;
  int correctAttempts;
  DateTime? lastAttempt;

  SrItem({
    required this.fen,
    required this.solution,
    required this.description,
    this.continuation = const [],
    this.source = 'review',
    this.interval = 0,
    DateTime? nextReview,
    this.timesCorrect = 0,
    this.attempts = 0,
    this.correctAttempts = 0,
    this.lastAttempt,
  }) : nextReview = nextReview ?? DateTime.now();

  /// Ignore move counters, but retain side, castling and en-passant rights.
  String get id => '${fen.split(' ').take(4).join(' ')}|$solution';
  bool get isDue => !nextReview.isAfter(DateTime.now());
  bool get isLearned => timesCorrect > _intervals.length;

  void markCorrect({DateTime? now}) {
    final at = now ?? DateTime.now();
    attempts++;
    correctAttempts++;
    lastAttempt = at;
    timesCorrect++;
    interval = (timesCorrect - 1).clamp(0, _intervals.length - 1);
    nextReview = at.add(Duration(days: _intervals[interval]));
  }

  void markIncorrect({DateTime? now}) {
    final at = now ?? DateTime.now();
    attempts++;
    lastAttempt = at;
    timesCorrect = 0;
    interval = 0;
    nextReview = at.add(const Duration(days: 1));
  }

  Map<String, dynamic> toJson() => {
    'fen': fen,
    'solution': solution,
    'description': description,
        'continuation': continuation,
        'source': source,
        'interval': interval,
    'nextReview': nextReview.toIso8601String(),
    'timesCorrect': timesCorrect,
        'attempts': attempts,
        'correctAttempts': correctAttempts,
        'lastAttempt': lastAttempt?.toIso8601String(),
  };

  factory SrItem.fromJson(Map<String, dynamic> json) => SrItem(
    fen: json['fen'] as String,
    solution: json['solution'] as String,
    description: json['description'] as String? ?? '',
        continuation:
            (json['continuation'] as List?)?.cast<String>() ?? const [],
        source: json['source'] as String? ?? 'review',
        interval:
            (json['interval'] as int? ?? 0).clamp(0, _intervals.length - 1),
    nextReview: DateTime.tryParse(json['nextReview'] as String? ?? '') ?? DateTime.now(),
    timesCorrect: json['timesCorrect'] as int? ?? 0,
        attempts: json['attempts'] as int? ?? 0,
        correctAttempts: json['correctAttempts'] as int? ?? 0,
        lastAttempt: DateTime.tryParse(json['lastAttempt'] as String? ?? ''),
  );

  String encode() => jsonEncode(toJson());
  static SrItem decode(String s) => SrItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

List<SrItem> getDueItems(List<SrItem> items) =>
    items.where((item) => item.isDue && !item.isLearned).toList()
    ..sort((a, b) => a.nextReview.compareTo(b.nextReview));
