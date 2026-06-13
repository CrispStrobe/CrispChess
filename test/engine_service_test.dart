import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/services/engine_service.dart';

void main() {
  group('EngineEvent types', () {
    test('EvalUpdateEvent holds data', () {
      final e = EvalUpdateEvent(eval: 1.5, depth: 20, bestMove: 'e2e4');
      expect(e.eval, 1.5);
      expect(e.depth, 20);
      expect(e.bestMove, 'e2e4');
    });

    test('BestMoveEvent holds move', () {
      expect(BestMoveEvent('d2d4').move, 'd2d4');
    });

    test('EngineErrorEvent holds message', () {
      expect(EngineErrorEvent('fail').message, 'fail');
    });

    test('pattern matching exhaustive', () {
      final events = <EngineEvent>[
        EvalUpdateEvent(eval: 0.5, depth: 10, bestMove: 'e2e4'),
        BestMoveEvent('d2d4'),
        StateChangeEvent(EngineState.ready),
        EngineErrorEvent('test'),
      ];
      final results = events.map((e) => switch (e) {
        EvalUpdateEvent() => 'eval',
        BestMoveEvent() => 'best',
        StateChangeEvent() => 'state',
        EngineErrorEvent() => 'error',
      }).toList();
      expect(results, ['eval', 'best', 'state', 'error']);
    });
  });

  group('StateChangeEvent', () {
    test('holds all EngineState values', () {
      for (final s in EngineState.values) {
        expect(StateChangeEvent(s).state, s);
      }
    });
  });

  group('Debounce behavior', () {
    test('rapid events debounce to one', () async {
      final controller = StreamController<EngineEvent>.broadcast();
      final events = <EngineEvent>[];
      controller.stream.listen(events.add);

      Timer? debounce;
      double? buffered;
      for (int i = 0; i < 50; i++) {
        buffered = i * 0.02;
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 50), () {
          controller.add(EvalUpdateEvent(
              eval: buffered!, depth: 50, bestMove: 'e2e4'));
        });
      }

      await Future.delayed(const Duration(milliseconds: 150));
      expect(events.length, 1);
      expect((events.first as EvalUpdateEvent).eval, closeTo(0.98, 0.01));

      debounce?.cancel();
      await controller.close();
    });
  });
}
