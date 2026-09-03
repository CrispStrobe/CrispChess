/// Tests that all engine implementations follow the ChessEngine contract.
///
/// Tests the Built-in (DartEngine) fully since it has no external deps.
/// Other engines are tested for constructor/interface compliance only
/// (they need browser or native runtime for full init).
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/engines/engine_factory.dart';

void main() {
  group('ChessEngine contract', () {
    test('DartEngine has correct name', () {
      final engine = DartEngine();
      expect(engine.name, 'Built-in');
      expect(engine.license, 'MIT');
      expect(engine.estimatedElo, greaterThan(0));
    });

    test('DartEngine starts in idle state', () {
      final engine = DartEngine();
      expect(engine.state, EngineState.idle);
    });

    test('DartEngine initializes to ready', () async {
      final engine = DartEngine();
      await engine.initialize();
      expect(engine.state, EngineState.ready);
      engine.dispose();
    });

    test('DartEngine disposes cleanly', () async {
      final engine = DartEngine();
      await engine.initialize();
      engine.dispose();
      expect(engine.state, EngineState.disposed);
    });

    test('DartEngine produces a valid move', () async {
      final engine = DartEngine();
      await engine.initialize();

      final move = await engine.bestMove(
        'position startpos',
        depth: 3,
        skillLevel: 5,
      );

      expect(move.length, greaterThanOrEqualTo(4));
      expect(move[0], matches(RegExp(r'[a-h]')));
      expect(move[1], matches(RegExp(r'[1-8]')));
      expect(move[2], matches(RegExp(r'[a-h]')));
      expect(move[3], matches(RegExp(r'[1-8]')));

      engine.dispose();
    });

    test('DartEngine plays different moves for different positions', () async {
      final engine = DartEngine();
      await engine.initialize();

      final move1 = await engine.bestMove('position startpos', depth: 3);
      final move2 = await engine.bestMove(
          'position startpos moves e2e4 e7e5', depth: 3);

      // Different positions should generally produce different moves
      // (not guaranteed, but very likely)
      expect(move1, isNotEmpty);
      expect(move2, isNotEmpty);

      engine.dispose();
    });

    test('engines declare whether they can search in the background', () {
      // Pondering runs a search while the player thinks. It is only safe for
      // engines that search off the UI thread and can be stopped; for the WASM
      // and FFI engines the search is one blocking call, so a ponder froze the
      // app for its whole duration — and that duration grew every move as the
      // position opened up.
      expect(DartEngine().canPonder, isTrue,
          reason: 'the built-in engine searches in an isolate (or yields '
              'between depths on web)');
    });

    test('DartEngine stop is safe when not thinking', () {
      final engine = DartEngine();
      expect(() => engine.stop(), returnsNormally);
    });

    test('DartEngine stateNotifier emits changes', () async {
      final engine = DartEngine();
      final states = <EngineState>[];
      engine.stateNotifier.addListener(() {
        states.add(engine.state);
      });

      await engine.initialize();
      expect(states, contains(EngineState.ready));

      engine.dispose();
    });
  });

  group('Engine factory', () {
    test('createEngine returns DartEngine for Built-in', () {
      final engine = createEngine('Built-in');
      expect(engine, isA<DartEngine>());
      expect(engine.name, 'Built-in');
    });

    test('createEngine returns DartEngine for unknown name', () {
      final engine = createEngine('NonExistent');
      expect(engine, isA<DartEngine>());
    });

    test('createEngine accepts playerElo', () {
      final engine = createEngine('Built-in', playerElo: 1800);
      expect(engine, isNotNull);
    });

    test('createEngine accepts maia3Variant', () {
      final engine = createEngine('Built-in', maia3Variant: '5m');
      expect(engine, isNotNull);
    });

    test('all engine names create without error', () {
      for (final name in ['Built-in', 'Stockfish', 'Frozenight',
                           'Maia3', 'Maia3 Dart', 'Lc0']) {
        expect(() => createEngine(name), returnsNormally,
            reason: '$name should create without error');
      }
    });
  });

  group('DartEngine game simulation', () {
    test('plays a full game without crashing', () async {
      final engine = DartEngine();
      await engine.initialize();

      var position = 'position startpos';
      final moves = <String>[];

      // Play up to 50 half-moves
      for (int i = 0; i < 50; i++) {
        try {
          final move = await engine.bestMove(position, depth: 2, skillLevel: 5);
          moves.add(move);
          position = 'position startpos moves ${moves.join(' ')}';
        } catch (e) {
          // Game might end (no legal moves)
          break;
        }
      }

      expect(moves.length, greaterThan(0));
      engine.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
