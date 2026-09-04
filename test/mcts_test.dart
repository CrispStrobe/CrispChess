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
import 'package:chess/chess.dart' as chess;
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

  group('mctsSearch simulations', () {
    // The loop used to score every leaf with the *root's* value scaled by
    // depth, which is not a search: the visit counts carried no information the
    // policy did not already have, and the iterations were pure cost. These
    // check that a simulation now evaluates the position it actually reached.

    test('without a resolver it does not pretend to search', () async {
      var evaluations = 0;
      final move = await mctsSearch(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        legalMoves: _legal,
        evaluate: (_, __) async {
          evaluations++;
          return _eval();
        },
        config: const MctsConfig(maxNodes: 500, maxTime: Duration(seconds: 5)),
      );
      expect(move, 'e2e4');
      expect(evaluations, 1,
          reason: 'only the root can be scored, so only the root is evaluated '
              '— 500 iterations of nothing is not a search');
    });

    test('with a resolver each simulation evaluates its own position',
        () async {
      final seen = <String>[];
      await mctsSearch(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        legalMoves: _legal,
        evaluate: (fen, _) async {
          seen.add(fen);
          return _eval();
        },
        positionAt: (moves) {
          final board = chess.Chess();
          for (final uci in moves) {
            board.move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
          }
          return MctsPosition(
            fen: board.fen,
            legalMoves: [
              for (final m in board.generate_moves())
                '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
            ],
          );
        },
        config: const MctsConfig(maxNodes: 12, maxTime: Duration(seconds: 20)),
      );

      expect(seen.length, 13, reason: 'the root plus one per simulation');
      expect(seen.toSet().length, greaterThan(1),
          reason: 'different positions, not the root over and over');
      // Once a child has been visited its own children become selectable, so
      // some evaluations are two plies deep. That is the tree being built.
      expect(seen.skip(1).any((f) => f.split(' ')[1] == 'w'), isTrue,
          reason: 'the search should reach past the first ply');
    });

    test('a mate found in the tree is scored as a mate', () async {
      // Back-rank mate in one: after Ra8 Black has no move.
      const fen = '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1';
      final board = chess.Chess.fromFEN(fen);
      final legal = [
        for (final m in board.generate_moves())
          '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
      ];

      final move = await mctsSearch(
        fen: fen,
        legalMoves: legal,
        // A flat policy and a neutral value, so only the terminal score can
        // single out the mate.
        evaluate: (_, moves) async => NnEval(
          value: 0.0,
          policy: {for (final m in moves) m: 1.0 / moves.length},
        ),
        positionAt: (moves) {
          final b = chess.Chess.fromFEN(fen);
          for (final uci in moves) {
            b.move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
          }
          final l = [
            for (final m in b.generate_moves())
              '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
          ];
          if (l.isEmpty) {
            return MctsPosition(
                fen: b.fen,
                legalMoves: const [],
                terminalValue: b.in_check ? -1.0 : 0.0);
          }
          return MctsPosition(fen: b.fen, legalMoves: l);
        },
        config: const MctsConfig(maxNodes: 80, maxTime: Duration(seconds: 20)),
      );
      expect(move, 'a1a8');
    });
  });
}
