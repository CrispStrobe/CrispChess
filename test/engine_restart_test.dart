// An engine whose process dies should not end the game.
//
// Before a death could be told from a timeout there was nothing safe to do
// about one: the app showed a red snackbar, cleared "thinking", and left the
// dead process in place, so every later move failed the same way until someone
// noticed and switched engines by hand. Now that the two are distinguishable,
// the service replaces it and asks again.
@TestOn('vm')
library;

import 'dart:async';

import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/services/engine_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers `e2e4`, or dies first if it was built to.
class _Stub implements ChessEngine {
  _Stub({this.diesOnMove = false});

  final bool diesOnMove;
  static int built = 0;
  static int disposed = 0;

  final _notifier = ValueNotifier<EngineState>(EngineState.idle);
  bool initialized = false;

  @override
  Future<void> initialize() async {
    initialized = true;
    _Stub.built++;
    _notifier.value = EngineState.ready;
  }

  @override
  Future<String> bestMove(String positionCommand,
      {int? depth, Duration? moveTime, int? skillLevel}) async {
    if (diesOnMove) {
      throw EngineProcessDiedException('Stub', 9, const ['it exploded']);
    }
    return 'e2e4';
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand,
          {int? depth, bool infinite = false}) =>
      const Stream.empty();

  @override
  void dispose() {
    _Stub.disposed++;
    _notifier.value = EngineState.disposed;
  }

  @override
  String get name => 'Stub';
  @override
  String get version => '1';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 1000;
  @override
  EngineState get state => _notifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _notifier;
  @override
  bool get canPonder => false;
  @override
  void stop() {}
  @override
  void setOption(String name, String value) {}
}

Future<T> _firstWhere<T>(Stream<EngineEvent> events, bool Function(T) test) =>
    events.where((e) => e is T && test(e as T)).cast<T>().first;

void main() {
  setUp(() {
    _Stub.built = 0;
    _Stub.disposed = 0;
  });

  test('a dead engine is replaced and the move still arrives', () async {
    final service = EngineService(
      _Stub(diesOnMove: true),
      rebuildEngine: () => _Stub(),
    );
    // The book answers from the start position before the engine is asked.
    service.useOpeningBook = false;
    await service.initialize();

    final move = _firstWhere<BestMoveEvent>(service.events, (_) => true);
    await service.requestMove('position startpos', skillLevel: 10);

    expect((await move.timeout(const Duration(seconds: 5))).move, 'e2e4');
    expect(_Stub.disposed, 1, reason: 'the dead one is disposed, not leaked');
    expect(_Stub.built, 2, reason: 'built once, then rebuilt once');
    service.dispose();
  });

  test('without a way to rebuild, the death is reported and play stops',
      () async {
    final service = EngineService(_Stub(diesOnMove: true));
    // The book answers from the start position before the engine is asked.
    service.useOpeningBook = false;
    await service.initialize();

    final failure = _firstWhere<EngineErrorEvent>(service.events, (_) => true);
    await service.requestMove('position startpos', skillLevel: 10);

    final message = (await failure.timeout(const Duration(seconds: 5))).message;
    expect(message, contains('exited while searching'));
    expect(message, contains('exit code 9'));
    expect(message, contains('it exploded'),
        reason: 'the stderr is the point of reporting a death at all');
    service.dispose();
  });

  test('an engine that keeps dying is not restarted forever', () async {
    final service = EngineService(
      _Stub(diesOnMove: true),
      rebuildEngine: () => _Stub(diesOnMove: true),
    );
    // The book answers from the start position before the engine is asked.
    service.useOpeningBook = false;
    await service.initialize();

    for (var i = 0; i < 6; i++) {
      await service.requestMove('position startpos', skillLevel: 10);
    }
    // One original plus at most the restart cap.
    expect(_Stub.built, lessThanOrEqualTo(4),
        reason: 'restarting on every move turns one bad engine into an '
            'unusable app');
    service.dispose();
  });
}
