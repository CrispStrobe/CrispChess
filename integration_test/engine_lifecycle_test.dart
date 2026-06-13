import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/services/engine_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EngineService lifecycle with DartEngine', (tester) async {
    final service = EngineService(DartEngine());
    final events = <EngineEvent>[];
    service.events.listen(events.add);

    await service.initialize();
    await Future.delayed(const Duration(milliseconds: 100));
    expect(events.any((e) => e is StateChangeEvent && e.state == EngineState.ready), isTrue);

    await service.requestMove('position startpos', depth: 3);
    await Future.delayed(const Duration(seconds: 5));
    expect(events.any((e) => e is BestMoveEvent), isTrue);

    service.dispose();
  });

  testWidgets('DartEngine plays a complete game against itself', (tester) async {
    final engine = DartEngine();
    await engine.initialize();

    String position = 'position startpos';
    final moves = <String>[];

    for (int i = 0; i < 20; i++) {
      final posCmd = moves.isEmpty
          ? 'position startpos'
          : 'position startpos moves ${moves.join(' ')}';
      final move = await engine.bestMove(posCmd, depth: 2);
      moves.add(move);
    }

    expect(moves.length, 20);
    expect(moves.every((m) => m.length >= 4), isTrue);

    engine.dispose();
  });
}
