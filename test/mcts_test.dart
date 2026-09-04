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
  group('NnEvalCache', () {
    test('reuses an evaluation with the same position and history', () async {
      final cache = NnEvalCache();
      var evaluations = 0;
      Future<NnEval> evaluate(
          String _, List<String> __, List<String> ___) async {
        evaluations++;
        return _eval();
      }

      final first =
          await cache.evaluate('fen', _legal, const ['old'], evaluate);
      final second =
          await cache.evaluate('fen', _legal, const ['old'], evaluate);

      expect(identical(first, second), isTrue);
      expect(evaluations, 1);
    });

    test('history and legal moves are part of the cache key', () async {
      final cache = NnEvalCache();
      var evaluations = 0;
      Future<NnEval> evaluate(
          String _, List<String> __, List<String> ___) async {
        evaluations++;
        return _eval();
      }

      await cache.evaluate('fen', _legal, const ['line-a'], evaluate);
      await cache.evaluate('fen', _legal, const ['line-b'], evaluate);
      await cache.evaluate('fen', const ['e2e4'], const ['line-b'], evaluate);

      expect(evaluations, 3);
    });

    test('evicts the least recently used evaluation', () async {
      final cache = NnEvalCache(capacity: 2);
      var evaluations = 0;
      Future<NnEval> evaluate(
          String _, List<String> __, List<String> ___) async {
        evaluations++;
        return _eval();
      }

      await cache.evaluate('a', _legal, const [], evaluate);
      await cache.evaluate('b', _legal, const [], evaluate);
      await cache.evaluate('a', _legal, const [], evaluate); // Touch a.
      await cache.evaluate('c', _legal, const [], evaluate); // Evicts b.
      await cache.evaluate('b', _legal, const [], evaluate);

      expect(evaluations, 4);
      expect(cache.length, 2);
    });

    test('does not retain failed evaluations', () async {
      final cache = NnEvalCache();
      var evaluations = 0;
      Future<NnEval> evaluate(
          String _, List<String> __, List<String> ___) async {
        evaluations++;
        if (evaluations == 1) throw StateError('transient');
        return _eval();
      }

      await expectLater(
          cache.evaluate('fen', _legal, const [], evaluate), throwsStateError);
      await cache.evaluate('fen', _legal, const [], evaluate);

      expect(evaluations, 2);
    });
  });

  group('mctsSearch', () {
    test('returns the network\'s choice when no simulation had time to run',
        () async {
      final move = await mctsSearch(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        legalMoves: _legal,
        evaluate: (_, __, ___) async => _eval(),
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
        evaluate: (_, __, ___) async => _eval(),
        config: const MctsConfig(maxNodes: 400, maxTime: Duration(seconds: 5)),
      );
      expect(move, 'e2e4');
    });

    test('a forced move is returned without evaluating anything', () async {
      var evaluated = false;
      final move = await mctsSearch(
        fen: '7k/8/8/8/8/8/8/K6R w - - 0 1',
        legalMoves: const ['h1h8'],
        evaluate: (_, __, ___) async {
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
        evaluate: (_, __, ___) async {
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
        evaluate: (fen, _, __) async {
          seen.add(fen);
          return _eval();
        },
        positionAt: (moves) {
          final board = chess.Chess();
          for (final uci in moves) {
            board
                .move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
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

    test('batches distinct leaves and preserves the simulation budget',
        () async {
      var individualEvaluations = 0;
      final batchSizes = <int>[];
      final seenInBatches = <String>[];

      MctsPosition resolve(List<String> moves) {
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
      }

      await mctsSearch(
        fen: chess.Chess().fen,
        legalMoves: _legal,
        evaluate: (_, __, ___) async {
          individualEvaluations++;
          return _eval();
        },
        evaluateBatch: (positions) async {
          batchSizes.add(positions.length);
          seenInBatches.addAll(positions.map((p) => p.fen));
          return [for (final _ in positions) _eval()];
        },
        batchSize: 4,
        positionAt: resolve,
        config: const MctsConfig(maxNodes: 8, maxTime: Duration(seconds: 20)),
      );

      expect(individualEvaluations, 1, reason: 'only the root is unbatched');
      expect(batchSizes, [4, 4]);
      expect(seenInBatches.toSet().length, seenInBatches.length,
          reason: 'virtual loss should reserve a different leaf per slot');
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
        evaluate: (_, moves, __) async => NnEval(
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

  group('mctsSearch history', () {
    // Lc0-style networks read the previous plies as input planes, so what a
    // leaf is told about its past changes what it says about its future.
    // Every leaf used to be handed the *root's* history, which describes a
    // game that diverged several moves ago — invisible in any check that
    // evaluates one position, and invisible on a budget too small to reach a
    // leaf at all.
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

    MctsPosition resolve(List<String> rootHistory, List<String> moves) {
      final board = chess.Chess.fromFEN(start);
      final history = <String>[...rootHistory, start];
      for (final uci in moves) {
        board.move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
        history.add(board.fen);
      }
      history.removeLast();
      return MctsPosition(
        fen: board.fen,
        historyFens: history,
        legalMoves: [
          for (final m in board.generate_moves())
            '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
        ],
      );
    }

    test('each evaluation is given the line that reached it', () async {
      const rootHistory = ['a-position-before-the-root'];
      final seen = <String, List<String>>{};

      await mctsSearch(
        fen: start,
        legalMoves: _legal,
        historyFens: rootHistory,
        evaluate: (fen, _, history) async {
          seen[fen] = history;
          return _eval();
        },
        positionAt: (moves) => resolve(rootHistory, moves),
        config: const MctsConfig(maxNodes: 6, maxTime: Duration(seconds: 20)),
      );

      expect(seen[start], rootHistory,
          reason: 'the root is handed exactly the history it was given');

      // Every leaf's history must end at the position immediately before it,
      // and must start with the root's own history.
      for (final entry in seen.entries) {
        if (entry.key == start) continue;
        expect(entry.value.first, rootHistory.first);
        expect(entry.value, contains(start),
            reason: 'the root is part of a leaf\'s past');
        expect(entry.value, isNot(contains(entry.key)),
            reason: 'a position is not part of its own history');
        expect(entry.value.length, greaterThan(rootHistory.length),
            reason: 'a leaf has more history than the root did');
      }
      expect(seen.length, greaterThan(1));
    });
  });

  group('mctsSearch on a tiny budget', () {
    // One simulation used to be worse than none. With no simulations the
    // fallback returns the highest prior; with exactly one, a single child
    // ends up with a visit and wins on visit count — and which child that was
    // had nothing to do with the network, because the first selection scored
    // every child at zero and took the first one generated.
    test('one simulation still returns the network\'s choice', () async {
      final move = await mctsSearch(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        legalMoves: _legal,
        evaluate: (_, __, ___) async => _eval(),
        positionAt: (moves) {
          final board = chess.Chess();
          for (final uci in moves) {
            board
                .move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
          }
          return MctsPosition(
            fen: board.fen,
            legalMoves: [
              for (final m in board.generate_moves())
                '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
            ],
          );
        },
        config: const MctsConfig(maxNodes: 1, maxTime: Duration(seconds: 20)),
      );
      expect(move, 'e2e4',
          reason: 'a2a3 is what the move generator offers first, and what the '
              'search returned while the prior was cancelled out');
    });
  });
}
