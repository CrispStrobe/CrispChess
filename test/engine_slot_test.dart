// Keeping an engine, and noticing when it can no longer be kept.
@TestOn('vm')
library;

import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_slot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stub implements ChessEngine {
  _Stub({EngineState state = EngineState.idle, this.disposeThrows = false})
      : _notifier = ValueNotifier<EngineState>(state);

  final ValueNotifier<EngineState> _notifier;
  final bool disposeThrows;
  static int built = 0;
  static int disposed = 0;
  bool initialised = false;

  @override
  Future<void> initialize() async {
    initialised = true;
    _notifier.value = EngineState.ready;
  }

  @override
  void dispose() {
    _Stub.disposed++;
    if (disposeThrows) throw StateError('already gone');
    _notifier.value = EngineState.disposed;
  }

  void die() => _notifier.value = EngineState.error;

  @override
  Future<String> bestMove(String p,
          {int? depth, Duration? moveTime, int? skillLevel}) async =>
      'e2e4';
  @override
  Stream<EvalInfo> analyze(String p, {int? depth, bool infinite = false}) =>
      const Stream.empty();
  @override
  String get name => 'Stub';
  @override
  String get version => '1';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 1;
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

EngineSlot _slot() => EngineSlot(() {
      _Stub.built++;
      return _Stub();
    });

void main() {
  setUp(() {
    _Stub.built = 0;
    _Stub.disposed = 0;
  });

  test('builds once and initialises it', () async {
    final slot = _slot();
    final engine = await slot.get();

    expect(_Stub.built, 1);
    expect((engine as _Stub).initialised, isTrue);
    expect(engine.state, EngineState.ready);
  });

  test('a healthy engine is kept, not rebuilt', () async {
    final slot = _slot();
    final first = await slot.get();
    final second = await slot.get();

    expect(identical(first, second), isTrue);
    expect(_Stub.built, 1);
    expect(slot.rebuilds, 0);
  });

  test('an engine whose process died is replaced', () async {
    final slot = _slot();
    final first = await slot.get() as _Stub;
    first.die(); // EngineState.error: not idle, and not disposed

    final second = await slot.get();

    expect(identical(first, second), isFalse,
        reason: 'the dead one used to be kept forever');
    expect(_Stub.built, 2);
    expect(_Stub.disposed, 1, reason: 'and released, not leaked');
    expect(second.state, EngineState.ready);
    expect(slot.rebuilds, 1);
  });

  test('a disposed engine is replaced too', () async {
    final slot = _slot();
    final first = await slot.get();
    first.dispose();

    expect(identical(await slot.get(), first), isFalse);
    expect(slot.rebuilds, 1);
  });

  test('an engine that throws on dispose is still let go of', () async {
    final slot = EngineSlot(() {
      _Stub.built++;
      return _Stub(disposeThrows: true);
    });
    final first = await slot.get() as _Stub;
    first.die();

    // The point of disposing is to stop holding it; failing at that must not
    // leave the caller stuck with the corpse.
    expect(identical(await slot.get(), first), isFalse);
    expect(_Stub.built, 2);
  });

  test('the predicate names exactly the unusable states', () {
    expect(engineNeedsRebuild(EngineState.error), isTrue);
    expect(engineNeedsRebuild(EngineState.disposed), isTrue);
    for (final ok in [
      EngineState.idle,
      EngineState.initializing,
      EngineState.ready,
      EngineState.thinking,
    ]) {
      expect(engineNeedsRebuild(ok), isFalse, reason: '$ok is usable');
    }
  });
}
