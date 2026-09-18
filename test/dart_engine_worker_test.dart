import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/engines/chess_engine.dart';

void main() {
  test('stop promptly cancels an active bestMove without late success',
      () async {
    final engine = DartEngine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final pending = engine.bestMove('position startpos',
        depth: 50, moveTime: const Duration(seconds: 10), skillLevel: 20);
    final cancelled = expectLater(pending, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    engine.stop();
    await cancelled.timeout(const Duration(milliseconds: 500));
    expect(engine.state, EngineState.ready);
  });
}
