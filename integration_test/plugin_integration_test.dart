import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DartEngine initializes and plays a move', (tester) async {
    final engine = DartEngine();
    await engine.initialize();
    expect(engine.state, EngineState.ready);

    final move = await engine.bestMove('position startpos', depth: 3);
    expect(move.length, greaterThanOrEqualTo(4));

    engine.dispose();
    expect(engine.state, EngineState.disposed);
  });
}
