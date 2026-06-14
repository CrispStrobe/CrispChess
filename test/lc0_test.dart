import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/lc0_dart/policy_map.dart';
import 'package:crispchess/engines/lc0_dart/mcts.dart';
import 'package:crispchess/engines/lc0_dart/variants.dart';

void main() {
  group('Lc0 Policy Map', () {
    test('has 1858 moves', () {
      final moves = getAllLc0Moves();
      expect(moves.length, 1858);
    });

    test('first move is a1b1', () {
      expect(indexToMove(0), 'a1b1');
    });

    test('move-to-index roundtrip works', () {
      final idx = moveToIndex('e2e4');
      expect(idx, isNotNull);
      expect(indexToMove(idx!), 'e2e4');
    });

    test('promotion moves are included', () {
      final idx = moveToIndex('a7a8q');
      expect(idx, isNotNull);
      expect(idx!, greaterThan(1790)); // Promotions are at the end
    });

    test('mirrorMove flips ranks correctly', () {
      expect(mirrorMove('e2e4'), 'e7e5');
      expect(mirrorMove('a7a8q'), 'a2a1q');
    });

    test('unknown move returns null', () {
      expect(moveToIndex('z9z9'), isNull);
    });
  });

  group('MCTS', () {
    test('MctsNode tracks visits and value', () {
      final node = MctsNode();
      node.backpropagate(0.5);
      expect(node.visits, 1);
      expect(node.q, 0.5);
    });

    test('MctsNode backpropagation flips value', () {
      final root = MctsNode();
      final child = MctsNode(move: 'e2e4', parent: root, prior: 0.5);
      root.children.add(child);

      child.backpropagate(0.8);

      expect(child.visits, 1);
      expect(child.q, 0.8);
      expect(root.visits, 1);
      expect(root.q, -0.8); // Flipped for opponent
    });

    test('bestChild returns most visited', () {
      final root = MctsNode();
      final c1 = MctsNode(move: 'e2e4', parent: root);
      final c2 = MctsNode(move: 'd2d4', parent: root);
      root.children.addAll([c1, c2]);

      c1.visits = 10;
      c2.visits = 20;

      expect(root.bestChild()?.move, 'd2d4');
    });

    test('MctsConfig scales with skill level', () {
      const config = MctsConfig();
      final easy = config.withSkillLevel(0);
      final hard = config.withSkillLevel(20);

      expect(easy.maxNodes, lessThan(hard.maxNodes));
      expect(easy.cpuct, greaterThan(hard.cpuct)); // More exploration
    });

    test('selectChild uses PUCT', () {
      final root = MctsNode();
      root.visits = 10;
      final c1 = MctsNode(move: 'e2e4', parent: root, prior: 0.9);
      final c2 = MctsNode(move: 'd2d4', parent: root, prior: 0.1);
      root.children.addAll([c1, c2]);

      // First selection should prefer c1 (higher prior)
      final selected = root.selectChild(2.5);
      expect(selected?.move, 'e2e4');
    });
  });

  group('Lc0 Variants', () {
    test('all Maia variants are defined', () {
      expect(getLc0Variant('1100'), isNotNull);
      expect(getLc0Variant('1500'), isNotNull);
      expect(getLc0Variant('1900'), isNotNull);
    });

    test('variant URLs point to HuggingFace', () {
      final v = getLc0Variant('1500');
      expect(v.url, contains('huggingface.co'));
      expect(v.url, contains('maia-1500'));
    });

    test('unknown variant throws', () {
      expect(() => getLc0Variant('9999'), throwsArgumentError);
    });

    test('lc0VariantFromMaia3 maps correctly', () {
      expect(lc0VariantFromMaia3('5m'), '1500');
      expect(lc0VariantFromMaia3('23m'), '1700');
      expect(lc0VariantFromMaia3('79m'), '1900');
    });
  });
}
