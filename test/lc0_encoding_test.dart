import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/lc0_dart/encoding.dart';
import 'package:crispchess/engines/lc0_dart/policy_map.dart';
import 'package:crispchess/engines/lc0_dart/mcts.dart';
import 'package:crispchess/engines/lc0_dart/variants.dart';

void main() {
  group('Lc0 Board Encoding', () {
    test('encodePosition produces 7168 elements (112*8*8)', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final planes = encodePosition(fen, []);
      expect(planes.length, 112 * 8 * 8);
    });

    test('encoding has non-zero values for starting position', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final planes = encodePosition(fen, []);
      final nonZero = planes.where((v) => v != 0).length;
      // 32 pieces + auxiliary planes should give many non-zero values
      expect(nonZero, greaterThan(30));
    });

    test('encoding changes after a move', () {
      const fen1 = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const fen2 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      final p1 = encodePosition(fen1, []);
      final p2 = encodePosition(fen2, []);
      // Should differ (different position)
      bool differs = false;
      for (int i = 0; i < p1.length; i++) {
        if (p1[i] != p2[i]) {
          differs = true;
          break;
        }
      }
      expect(differs, isTrue);
    });

    test('encoding handles black to move', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      final planes = encodePosition(fen, []);
      expect(planes.length, 112 * 8 * 8);
    });

    test('encoding handles endgame position', () {
      const fen = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';
      final planes = encodePosition(fen, []);
      expect(planes.length, 112 * 8 * 8);
      final nonZero = planes.where((v) => v != 0).length;
      // 3 pieces + aux planes
      expect(nonZero, greaterThan(2));
    });
  });

  group('Lc0 Policy Map', () {
    test('has exactly 1858 moves', () {
      expect(getAllLc0Moves().length, 1858);
    });

    test('all moves have valid format', () {
      for (final move in getAllLc0Moves()) {
        expect(move.length, greaterThanOrEqualTo(4));
        expect(move[0], matches(RegExp(r'[a-h]')));
        expect(move[1], matches(RegExp(r'[1-8]')));
        expect(move[2], matches(RegExp(r'[a-h]')));
        expect(move[3], matches(RegExp(r'[1-8]')));
        if (move.length > 4) {
          expect(move[4], matches(RegExp(r'[qrbn]')));
        }
      }
    });

    test('common moves are in the vocabulary', () {
      expect(moveToIndex('e2e4'), isNotNull);
      expect(moveToIndex('d2d4'), isNotNull);
      expect(moveToIndex('g1f3'), isNotNull);
      expect(moveToIndex('e1g1'), isNotNull); // kingside castle
    });

    test('moveToIndex returns null for invalid moves', () {
      expect(moveToIndex('z9z9'), isNull);
      expect(moveToIndex(''), isNull);
    });

    test('indexToMove roundtrips correctly', () {
      for (int i = 0; i < 1858; i++) {
        final move = indexToMove(i);
        expect(moveToIndex(move), i);
      }
    });

    test('mirrorMove flips ranks', () {
      expect(mirrorMove('e2e4'), 'e7e5');
      expect(mirrorMove('a1a8'), 'a8a1');
      expect(mirrorMove('e7e8q'), 'e2e1q');
    });
  });

  group('Lc0 MCTS', () {
    test('MctsNode initializes correctly', () {
      final node = MctsNode();
      expect(node.visits, 0);
      expect(node.totalValue, 0.0);
      expect(node.q, 0.0);
      expect(node.children, isEmpty);
    });

    test('backpropagate updates visits and flips value', () {
      final root = MctsNode();
      final child = MctsNode(move: 'e2e4', parent: root, prior: 0.3);
      root.children.add(child);

      child.backpropagate(0.7);

      expect(child.visits, 1);
      expect(child.q, closeTo(0.7, 0.001));
      expect(root.visits, 1);
      expect(root.q, closeTo(-0.7, 0.001));
    });

    test('selectChild prefers high prior for unvisited', () {
      final root = MctsNode();
      root.visits = 1;
      final c1 = MctsNode(move: 'e2e4', parent: root, prior: 0.8);
      final c2 = MctsNode(move: 'd2d4', parent: root, prior: 0.2);
      root.children.addAll([c1, c2]);

      final selected = root.selectChild(2.5);
      expect(selected?.move, 'e2e4');
    });

    test('bestChild returns most visited', () {
      final root = MctsNode();
      final c1 = MctsNode(move: 'e2e4', parent: root);
      final c2 = MctsNode(move: 'd2d4', parent: root);
      root.children.addAll([c1, c2]);
      c1.visits = 5;
      c2.visits = 15;

      expect(root.bestChild()?.move, 'd2d4');
    });

    test('movePath reconstructs from root to node', () {
      final root = MctsNode();
      final c1 = MctsNode(move: 'e2e4', parent: root);
      final c2 = MctsNode(move: 'e7e5', parent: c1);
      root.children.add(c1);
      c1.children.add(c2);

      expect(c2.movePath(), ['e2e4', 'e7e5']);
    });

    test('MctsConfig scales with skill level', () {
      const config = MctsConfig();
      final easy = config.withSkillLevel(0);
      final hard = config.withSkillLevel(20);

      expect(easy.maxNodes, lessThan(hard.maxNodes));
      expect(easy.cpuct, greaterThan(hard.cpuct));
    });

    test('mctsSearch returns a legal move', () async {
      final moves = ['e2e4', 'd2d4', 'g1f3', 'b1c3'];

      // Mock evaluator: uniform policy, neutral value
      Future<NnEval> mockEval(String fen, List<String> legalMoves) async {
        final policy = <String, double>{};
        for (final m in legalMoves) {
          policy[m] = 1.0 / legalMoves.length;
        }
        return NnEval(policy: policy, value: 0.0);
      }

      final result = await mctsSearch(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        legalMoves: moves,
        evaluate: mockEval,
        config: const MctsConfig(maxNodes: 50, maxTime: Duration(seconds: 1)),
      );

      expect(moves, contains(result));
    });

    test('mctsSearch with single move returns it immediately', () async {
      Future<NnEval> mockEval(String fen, List<String> legalMoves) async {
        return NnEval(policy: {'e2e4': 1.0}, value: 0.5);
      }

      final result = await mctsSearch(
        fen: 'test',
        legalMoves: ['e2e4'],
        evaluate: mockEval,
      );
      expect(result, 'e2e4');
    });
  });

  group('Lc0 Variants', () {
    test('all variants have HuggingFace URLs', () {
      for (final v in lc0Variants) {
        expect(v.url, contains('huggingface.co'));
        expect(v.url, contains('opset15'));
      }
    });

    test('ELO range is 1100-1900', () {
      final elos = lc0Variants.map((v) => v.estimatedElo).toList();
      expect(elos.first, 1100);
      expect(elos.last, 1900);
    });

    test('getLc0Variant returns correct variant', () {
      expect(getLc0Variant('1500').estimatedElo, 1500);
      expect(getLc0Variant('1100').displayName, 'Maia 1100');
    });

    test('getLc0Variant returns default for unknown', () {
      final v = getLc0Variant('9999');
      expect(v.id, defaultLc0Variant);
    });

    test('lc0VariantFromMaia3 maps correctly', () {
      expect(lc0VariantFromMaia3('5m'), '1500');
      expect(lc0VariantFromMaia3('23m'), '1700');
      expect(lc0VariantFromMaia3('79m'), '1900');
      expect(lc0VariantFromMaia3('unknown'), defaultLc0Variant);
    });
  });
}
