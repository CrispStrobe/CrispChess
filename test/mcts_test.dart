// The MCTS used by the Lc0 engines evaluates the root with one network forward
// pass and then runs simulations within whatever budget is left. On a tight
// budget — or on the first, cold call of a session — that pass can consume the
// whole budget and no simulation runs at all.
//
// When that happened every child had zero visits, and picking "the most visited
// child" returned `children.first`: whichever move the move generator happened
// to emit first. From the starting position that is a2a3, regardless of the
// network giving e2e4 a policy of 13.1 and a2a3 far less. These tests pin the
// fallback to the network's own preference.
import 'package:crispchess/engines/lc0_dart/mcts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Move list in generator order: a-file pawn first, the good move late.
const _legal = ['a2a3', 'a2a4', 'b2b3', 'g1f3', 'd2d4', 'e2e4'];

NnEval _eval() => NnEval(
      value: 0.05,
      policy: const {
        'a2a3': 0.02,
        'a2a4': 0.03,
        'b2b3': 0.02,
        'g1f3': 0.15,
        'd2d4': 0.28,
        'e2e4': 0.50,
      },
    );

void main() {
  group('mctsSearch', () {
    test('returns the network\'s choice when no simulation had time to run',
        () async {
      final move = await mctsSearch(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        legalMoves: _legal,
        evaluate: (_, __) async => _eval(),
        // Zero budget: the root evaluation happens, the loop does not.
        config: const MctsConfig(maxNodes: 800, maxTime: Duration.zero),
      );
      expect(move, 'e2e4',
          reason: 'with no visits to compare, the highest prior must win — '
              'not the first move the generator produced');
    });

    test('returns the network\'s choice when it does have time', () async {
      final move = await mctsSearch(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        legalMoves: _legal,
        evaluate: (_, __) async => _eval(),
        config: const MctsConfig(maxNodes: 400, maxTime: Duration(seconds: 5)),
      );
      expect(move, 'e2e4');
    });

    test('a forced move is returned without evaluating anything', () async {
      var evaluated = false;
      final move = await mctsSearch(
        fen: '7k/8/8/8/8/8/8/K6R w - - 0 1',
        legalMoves: const ['h1h8'],
        evaluate: (_, __) async {
          evaluated = true;
          return _eval();
        },
      );
      expect(move, 'h1h8');
      expect(evaluated, isFalse);
    });

    test('bestChild breaks ties on the prior', () {
      final root = MctsNode();
      for (final entry in {'a2a3': 0.02, 'e2e4': 0.5, 'd2d4': 0.3}.entries) {
        root.children
            .add(MctsNode(move: entry.key, parent: root, prior: entry.value));
      }
      expect(root.bestChild()!.move, 'e2e4');

      // A visited child still outranks an unvisited one with a better prior.
      root.children.first.visits = 1;
      expect(root.bestChild()!.move, 'a2a3');
    });
  });
}
