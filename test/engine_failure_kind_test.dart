// What kind of failure the service reports.
//
// The screen decides what to tell a player from this: a crash being recovered
// from is orange and does not clear "thinking", a crash that ended the game is
// red and names the way out, analysis trouble is not news about the game at
// all. All four used to be one red banner carrying a raw exception string, so
// the categorisation is now load-bearing and had nothing checking it.
@TestOn('vm')
library;

import 'dart:async';

import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/services/engine_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails a move the way a given engine would.
class _Failing implements ChessEngine {
  _Failing(this.error);

  final Object error;
  final _notifier = ValueNotifier<EngineState>(EngineState.idle);

  @override
  Future<void> initialize() async => _notifier.value = EngineState.ready;

  @override
  Future<String> bestMove(String positionCommand,
          {int? depth, Duration? moveTime, int? skillLevel}) async =>
      throw error;

  @override
  Stream<EvalInfo> analyze(String positionCommand,
          {int? depth, bool infinite = false}) =>
      Stream<EvalInfo>.error(error);

  @override
  void dispose() {}
  @override
  String get name => 'Failing';
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

Future<EngineErrorEvent> _failureFrom(EngineService service,
    Future<void> Function() act) async {
  final failure = service.events
      .where((e) => e is EngineErrorEvent)
      .cast<EngineErrorEvent>()
      .first;
  await act();
  return failure.timeout(const Duration(seconds: 5));
}

EngineService _serviceFor(Object error) {
  final service = EngineService(_Failing(error));
  service.useOpeningBook = false;
  return service;
}

void main() {
  test('a timeout is a timeout', () async {
    final service = _serviceFor(
        TimeoutException('No bestmove within 6800ms',
            const Duration(milliseconds: 6800)));
    await service.initialize();

    final failure = await _failureFrom(service,
        () => service.requestMove('position startpos', skillLevel: 10));

    expect(failure.kind, EngineFailure.timeout);
    expect(failure.recovering, isFalse);
    service.dispose();
  });

  test('a death with no way to rebuild is reported as final', () async {
    final service =
        _serviceFor(EngineProcessDiedException('Stub', 3, const ['boom']));
    await service.initialize();

    final failure = await _failureFrom(service,
        () => service.requestMove('position startpos', skillLevel: 10));

    expect(failure.kind, EngineFailure.died);
    expect(failure.recovering, isFalse,
        reason: 'nothing is coming, so the player has to be told what to do');
    service.dispose();
  });

  test('a death that is being recovered from says so', () async {
    final service = EngineService(
      _Failing(EngineProcessDiedException('Stub', 3, const ['boom'])),
      rebuildEngine: () => _Failing(TimeoutException('later')),
    );
    service.useOpeningBook = false;
    await service.initialize();

    final failure = await _failureFrom(service,
        () => service.requestMove('position startpos', skillLevel: 10));

    expect(failure.kind, EngineFailure.died);
    expect(failure.recovering, isTrue,
        reason: 'the board must not stop saying the engine is thinking');
    service.dispose();
  });

  test('anything else stays generic', () async {
    final service = _serviceFor(StateError('No legal moves'));
    await service.initialize();

    final failure = await _failureFrom(service,
        () => service.requestMove('position startpos', skillLevel: 10));

    expect(failure.kind, EngineFailure.other);
    service.dispose();
  });

  test('analysis trouble is not reported as trouble with the game', () async {
    final service = _serviceFor(StateError('inference failed'));
    await service.initialize();

    final failure = await _failureFrom(
        service, () => service.requestAnalysis('position startpos', depth: 12));

    expect(failure.kind, EngineFailure.analysis);
    service.dispose();
  });
}
