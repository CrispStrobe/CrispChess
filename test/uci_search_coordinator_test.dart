// Regression tests for the reported symptom: a UCI engine that plays fine for
// a few moves and then stops moving altogether.
//
// The cause was UCI's one-search-at-a-time rule being broken. The app starts a
// background (ponder) search after every engine move; when the player moved it
// sent `stop` and immediately a new `position` + `go`. The aborted ponder
// search's `bestmove` arrived first and was handed back as the answer to the
// new request — a move computed for the *previous* position. Usually illegal,
// so the board rejected it and the UI sat on "thinking" forever. It only showed
// up a few moves in, because that is when the fixed-depth ponder search first
// took longer than the player's thinking time.
import 'package:crispchess/engines/uci_search_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for an engine connection: records what was sent and lets
/// the test decide when a `bestmove` comes back.
class _FakeEngine with UciSearchCoordinator {
  final List<String> sent = [];

  @override
  void sendUci(String command) => sent.add(command);

  /// Simulate the engine answering the search in flight.
  void replyBestMove(String? move) => finishSearch(move);
}

void main() {
  group('UciSearchCoordinator', () {
    test('a search resolves with its own bestmove', () async {
      final engine = _FakeEngine();
      final move = engine.startSearch(
          'position startpos', 'go movetime 500',
          awaitMove: true);
      await Future<void>.delayed(Duration.zero);

      expect(engine.sent, ['position startpos', 'go movetime 500']);
      expect(engine.isSearching, isTrue);

      engine.replyBestMove('e2e4');
      expect(await move, 'e2e4');
      expect(engine.isSearching, isFalse);
    });

    test('an aborted ponder search cannot answer the next move request',
        () async {
      final engine = _FakeEngine();

      // Ponder: analysis nobody is awaiting a move from.
      engine.startSearch('position startpos moves e2e4', 'go depth 12',
          awaitMove: false);
      await Future<void>.delayed(Duration.zero);
      engine.sent.clear();

      // Player moves; the app asks for a move for the new position.
      final request = engine.startSearch(
          'position startpos moves e2e4 e7e5', 'go movetime 1000',
          awaitMove: true);

      // The coordinator must stop and drain the ponder search first, so nothing
      // has been sent for the new one yet.
      await Future<void>.delayed(Duration.zero);
      expect(engine.sent, ['stop'],
          reason: 'new search must wait for the old one to finish');

      // Now the ponder search's leftover bestmove arrives — for the *old*
      // position. It must be swallowed, not returned as the answer.
      engine.replyBestMove('g1f3');
      await Future<void>.delayed(Duration.zero);

      expect(engine.sent,
          ['stop', 'position startpos moves e2e4 e7e5', 'go movetime 1000']);

      engine.replyBestMove('b8c6');
      expect(await request, 'b8c6');
    });

    test('a bestmove with nothing outstanding is discarded', () async {
      final engine = _FakeEngine();
      // Leftover from a search that was already abandoned.
      engine.replyBestMove('a2a3');

      final move =
          engine.startSearch('position startpos', 'go movetime 100', awaitMove: true);
      await Future<void>.delayed(Duration.zero);
      engine.replyBestMove('d2d4');
      expect(await move, 'd2d4');
    });

    test('quiesce returns immediately when the engine is idle', () async {
      final engine = _FakeEngine();
      await engine.quiesceSearch();
      expect(engine.sent, isEmpty);
    });

    test('a search that never answers is dropped so the next one can run',
        () async {
      final engine = _FakeEngine();
      engine.startSearch('position startpos', 'go infinite', awaitMove: false);
      await Future<void>.delayed(Duration.zero);

      // Engine never replies; quiesce gives up after its timeout.
      await engine.quiesceSearch(timeout: const Duration(milliseconds: 20));
      expect(engine.isSearching, isFalse);

      final move = engine.startSearch(
          'position startpos moves d2d4', 'go movetime 100',
          awaitMove: true);
      await Future<void>.delayed(Duration.zero);
      engine.replyBestMove('d7d5');
      expect(await move, 'd7d5');
    });

    test('an engine that reports (none) resolves the request with null',
        () async {
      final engine = _FakeEngine();
      final move = engine.startSearch('position startpos', 'go movetime 100',
          awaitMove: true);
      await Future<void>.delayed(Duration.zero);
      engine.replyBestMove(null);
      expect(await move, isNull);
    });
  });
}
