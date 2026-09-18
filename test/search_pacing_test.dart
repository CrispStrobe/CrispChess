// The arithmetic that decides whether a move lands inside its budget.
//
// It was copied into four places, three of them in files `flutter test` cannot
// compile, so none of it had ever been checked — including the clamps, which
// are the parts that only matter when something has already gone wrong.
import 'package:crispchess/engines/search_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nodeAllowance', () {
    test('scales with the time left', () {
      expect(nodeAllowance(const Duration(milliseconds: 200), 500.0), 100000);
    });

    test('a spent budget still buys a legal move', () {
      // Returning zero here is an empty search and no move at all.
      expect(nodeAllowance(Duration.zero, 500.0), 4096);
      expect(nodeAllowance(const Duration(milliseconds: -5), 500.0), 4096);
    });

    test('a throughput not yet measured falls back to the floor', () {
      expect(nodeAllowance(const Duration(seconds: 1), 0), 4096);
      expect(nodeAllowance(const Duration(seconds: 1), -3), 4096);
    });

    test('a long budget stays inside what the other side can hold', () {
      // The value crosses into WASM and FFI as a fixed-width integer.
      expect(nodeAllowance(const Duration(hours: 1), 1e9), 2000000000);
    });
  });

  group('updatedRate', () {
    test('each measurement moves the estimate halfway', () {
      expect(updatedRate(1000, 100000, 50), 1500);
    });

    test('a low starting guess converges in about three searches', () {
      // It is averaged in like any other value, so this is what the engines
      // actually do from their conservative first estimate.
      var rate = 50.0;
      for (var i = 0; i < 3; i++) {
        rate = updatedRate(rate, 100000, 50); // a true 2000 nodes/ms
      }
      expect(rate, closeTo(1756, 1),
          reason: 'within 12% of the truth after three');
    });

    test('a sample too small to mean anything is ignored', () {
      // A search that returns instantly measures the clock, not the engine.
      expect(updatedRate(1000, 10, 1), 1000);
      expect(updatedRate(1000, 100000, 0), 1000);
    });
  });

  group('worthStartingDepth', () {
    const budget = Duration(milliseconds: 800);
    test('an eighth left is not enough', () {
      expect(worthStartingDepth(const Duration(milliseconds: 100), budget),
          isFalse);
      expect(worthStartingDepth(const Duration(milliseconds: 101), budget),
          isTrue);
    });
  });

  group('discountedBudget', () {
    test('takes the overhead off the top', () {
      expect(discountedBudget(const Duration(milliseconds: 300), 57),
          const Duration(milliseconds: 243));
    });

    test('an implausible overhead cannot starve the search', () {
      // 108ms of a 300ms budget is real and must be honoured; 250 is not.
      expect(discountedBudget(const Duration(milliseconds: 300), 108),
          const Duration(milliseconds: 192));
      expect(discountedBudget(const Duration(milliseconds: 300), 250),
          const Duration(milliseconds: 150));
    });

    test('no overhead measured yet means ask for the whole budget', () {
      expect(discountedBudget(const Duration(milliseconds: 300), 0),
          const Duration(milliseconds: 300));
    });
  });
}
