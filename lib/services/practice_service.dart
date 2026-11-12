import 'package:chess/chess.dart' as chess;
import '../chess/spaced_repetition.dart';
import 'game_review_service.dart';
import 'preferences_service.dart';
import 'daily_practice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent, deduplicated practice queue. Scheduling survives navigation,
/// restarts and re-analysis of the same game.
class PracticeService {
  final PreferencesService prefs;
  PracticeService(this.prefs);

  List<SrItem> get items {
    final result = <SrItem>[];
    for (final raw in prefs.srQueue) {
      try {
        final item = SrItem.decode(raw);
        final board = chess.Chess.fromFEN(item.fen);
        if (_legal(board, item.solution)) result.add(item);
      } catch (_) {/* Ignore corrupt/old records without losing the rest. */}
    }
    return result;
  }

  static bool _legal(chess.Chess board, String uci) =>
      uci.length >= 4 &&
      board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        if (uci.length == 5) 'promotion': uci[4]
      });

  bool add(SrItem item) {
    try {
      if (!_legal(chess.Chess.fromFEN(item.fen), item.solution)) return false;
    } catch (_) {
      return false;
    }
    final queue = items;
    if (queue.any((existing) => existing.id == item.id)) return false;
    queue.insert(0, item);
    prefs.saveSrQueue(queue.take(500).map((i) => i.encode()).toList());
    return true;
  }

  int collect(List<ReviewedMove> review, {required bool playerIsWhite}) {
    var added = 0;
    for (final move in review) {
      final evaluation = move.annotation.evaluation;
      if (!evaluation.isVerified ||
          !evaluation.isComplete ||
          evaluation.whiteToMove != playerIsWhite ||
          evaluation.centipawnLoss < 1 ||
          evaluation.bestMove.isEmpty ||
          evaluation.bestMove == move.annotation.move) continue;
      if (add(SrItem(
          fen: move.fen,
          solution: evaluation.bestMove,
          description: move.annotation.move,
          continuation: move.continuation))) added++;
    }
    return added;
  }

  void record(SrItem item, {required bool correct}) {
    final queue = items;
    final index = queue.indexWhere((i) => i.id == item.id);
    if (index < 0) return;
    final stored = queue[index];
    SharedPreferences.getInstance()
        .then((p) => DailyPracticeService(p).record('review', itemId: item.id));
    if (correct) {
      stored.markCorrect();
    } else {
      stored.markIncorrect();
    }
    prefs.saveSrQueue(queue.map((i) => i.encode()).toList());
    // Keep the active exercise in sync for immediate feedback.
    item.interval = stored.interval;
    item.nextReview = stored.nextReview;
    item.timesCorrect = stored.timesCorrect;
    item.attempts = stored.attempts;
    item.correctAttempts = stored.correctAttempts;
    item.lastAttempt = stored.lastAttempt;
  }

  void remove(String id) => prefs.saveSrQueue(
      items.where((i) => i.id != id).map((i) => i.encode()).toList());
}
