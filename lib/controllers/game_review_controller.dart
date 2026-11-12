import 'package:flutter/foundation.dart';
import '../services/game_review_service.dart';
import '../services/practice_service.dart';
import '../services/preferences_service.dart';

/// Owns analysis, cancellation and collection independently of the summary UI.
class GameReviewController extends ChangeNotifier {
  final GameReviewService Function() createService;
  GameReviewController({GameReviewService Function()? createService})
      : createService = createService ?? (() => GameReviewService());
  GameReviewService? _service;
  bool _disposed = false;
  List<ReviewedMove>? review;
  bool running = false;
  int done = 0;
  int saved = 0;
  Object? error;

  Future<void> start(String command, {required bool playerIsWhite}) async {
    if (running || _disposed) return;
    final service = createService();
    _service = service;
    running = true;
    error = null;
    done = 0;
    notifyListeners();
    bool current() => !_disposed && _service == service;
    try {
      final results = await service.review(command, onProgress: (value, total) {
        if (current()) {
          done = value;
          notifyListeners();
        }
      });
      if (!current()) return;
      final prefs = PreferencesService();
      await prefs.init();
      if (!current()) return;
      saved =
          PracticeService(prefs).collect(results, playerIsWhite: playerIsWhite);
      review = results;
    } catch (e) {
      if (current()) error = e;
    } finally {
      if (current()) {
        running = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    _service?.cancel();
    _service = null;
    running = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
