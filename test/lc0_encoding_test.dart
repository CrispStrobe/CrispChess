import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/lc0_dart/encoding.dart';
import 'package:crispchess/engines/lc0_dart/policy_map.dart';
import 'package:crispchess/engines/lc0_dart/mcts.dart';
import 'package:crispchess/engines/lc0_dart/variants.dart';

void main() {
  group('Lc0 Board Encoding', () {
    test('encodePosition produces 7168 elements (112*8*8)', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final planes = encodePosition(fen);
      expect(planes.length, 112 * 8 * 8);
    });

    test('encoding has non-zero values for starting position', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final planes = encodePosition(fen);
      final nonZero = planes.where((v) => v != 0).length;
      // 32 pieces + auxiliary planes should give many non-zero values
      expect(nonZero, greaterThan(30));
    });

    test('encoding changes after a move', () {
      const fen1 = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const fen2 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      final p1 = encodePosition(fen1);
      final p2 = encodePosition(fen2);
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
      final planes = encodePosition(fen);
      expect(planes.length, 112 * 8 * 8);
    });

    test('encoding handles endgame position', () {
      const fen = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';
      final planes = encodePosition(fen);
      expect(planes.length, 112 * 8 * 8);
      final nonZero = planes.where((v) => v != 0).length;
      expect(nonZero, greaterThan(2));
    });
  });

  group('Lc0 Policy Map', () {
    test('has exactly 1858 moves', () {
      expect(lc0Moves.length, 1858);
    });

    test('all moves have valid format', () {
      for (final move in lc0Moves) {
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
      final map = getMoveToIndex();
      expect(map['e2e4'], isNotNull);
      expect(map['d2d4'], isNotNull);
      expect(map['g1f3'], isNotNull);
      expect(map['e1g1'], isNotNull); // kingside castle
    });

    test('getMoveToIndex returns null for invalid moves', () {
      final map = getMoveToIndex();
      expect(map['z9z9'], isNull);
    });

    test('indexToMove roundtrips correctly', () {
      final map = getMoveToIndex();
      for (int i = 0; i < 1858; i++) {
        final move = indexToMove(i);
        expect(map[move], i);
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

  // The auxiliary planes, pinned to lc0's own encoder
  // (src/neural/encoder.cc, INPUT_CLASSICAL_112_PLANE). Two of these were
  // wrong for as long as the engine existed, and no test could see it: the
  // start position sets all four castling planes and has a rule-50 count of
  // zero, so a kingside/queenside swap and a factor of 100 both vanish there.
  // Every case below is therefore asymmetric or mid-game on purpose.
  group('Lc0 auxiliary planes', () {
    double planeValue(Float32List planes, int plane) => planes[plane * 64];

    bool planeIsConstant(Float32List planes, int plane) {
      final first = planes[plane * 64];
      for (var i = 1; i < 64; i++) {
        if (planes[plane * 64 + i] != first) return false;
      }
      return true;
    }

    // White may castle queenside only, Black kingside only — so each of the
    // four planes carries a different answer from its neighbour.
    const asymmetric =
        '1rbqkbnr/pppppppp/2n5/8/8/5N2/PPPPPPPP/RNBQKBR1 w Qk - 4 3';

    test('castling planes are queenside first, for both sides', () {
      final planes = encodePosition(asymmetric);
      expect(planeValue(planes, 104), 1.0, reason: 'we can castle queenside');
      expect(planeValue(planes, 105), 0.0, reason: 'we cannot castle kingside');
      expect(planeValue(planes, 106), 0.0,
          reason: 'they cannot castle queenside');
      expect(planeValue(planes, 107), 1.0, reason: 'they can castle kingside');
    });

    test('castling planes follow the side to move, not the colour', () {
      // Same rights, Black to move: "us" and "them" change places.
      final planes = encodePosition(
          '1rbqkbnr/pppppppp/2n5/8/8/5N2/PPPPPPPP/RNBQKBR1 b Qk - 4 3');
      expect(planeValue(planes, 104), 0.0, reason: 'Black has no queenside');
      expect(planeValue(planes, 105), 1.0, reason: 'Black has kingside');
      expect(planeValue(planes, 106), 1.0, reason: 'White has queenside');
      expect(planeValue(planes, 107), 0.0, reason: 'White has no kingside');
    });

    test('the rule-50 plane is a raw ply count, not a fraction', () {
      // Dividing by 100 is the "hectoplies" input format; the Maia networks
      // are classical, and are handed the count itself.
      expect(planeValue(encodePosition(asymmetric), 109), 4.0);
      expect(
          planeValue(
              encodePosition(
                  'r1bqkbnr/pppppppp/8/1N4N1/1n6/8/PPPPPPPP/R1BQKB1R w KQkq - 16 9'),
              109),
          16.0);
      expect(planeIsConstant(encodePosition(asymmetric), 109), isTrue);
    });

    test('side to move and the bias plane', () {
      final white = encodePosition(asymmetric);
      expect(planeValue(white, 108), 0.0);
      expect(planeValue(white, 111), 1.0);
      expect(planeValue(white, 110), 0.0, reason: 'the old move counter');
      final black = encodePosition(
          '1rbqkbnr/pppppppp/2n5/8/8/5N2/PPPPPPPP/RNBQKBR1 b Qk - 4 3');
      expect(planeValue(black, 108), 1.0);
    });
  });

  group('Lc0 repetition planes', () {
    // A slot's repetition plane describes the position in *that* slot at the
    // point it was played. Counting occurrences inside the eight-slot window
    // instead marks early slots as repetitions of positions that had not
    // happened yet.
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

    test('a fresh position repeats nothing', () {
      final planes = encodePosition(start);
      for (var slot = 0; slot < 8; slot++) {
        expect(planes[(slot * 13 + 12) * 64], 0.0, reason: 'slot $slot');
      }
    });

    test('only the slots that had already occurred are marked', () {
      // Knights out and back twice: the current position is the third time
      // the start position has stood on the board, and the position four
      // plies ago was the second — but the first two slots of history are
      // first-time positions.
      final history = <String>[];
      final board = chess.Chess();
      for (final uci in 'g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8'.split(' ')) {
        history.add(board.fen);
        board.move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
      }
      final planes = encodePosition(board.fen, historyFens: history);

      // Slot 0 is the current position, seen twice before.
      expect(planes[(0 * 13 + 12) * 64], 1.0);
      // Slot 4 is the same position one cycle earlier, seen once before.
      expect(planes[(4 * 13 + 12) * 64], 1.0);
      // The oldest slots are the first time those positions appeared.
      expect(planes[(5 * 13 + 12) * 64], 0.0);
      expect(planes[(6 * 13 + 12) * 64], 0.0);
      expect(planes[(7 * 13 + 12) * 64], 0.0);
    });
  });
}
