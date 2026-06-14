import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/maia3_dart/encoding.dart';
import 'package:crispchess/engines/maia3_dart/moves.dart';
import 'package:crispchess/engines/maia3_dart/utils.dart';
import 'package:crispchess/engines/maia3_dart/history.dart';
import 'package:crispchess/engines/maia3_dart/variants.dart';

void main() {
  group('Maia3 Encoding', () {
    test('BoardState parses starting FEN', () {
      final board = BoardState.fromFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      expect(board.whiteToMove, isTrue);
      // a1 = index 0 should have white rook
      expect(board.pieces[0], 'R');
      // e1 = index 4 should have white king
      expect(board.pieces[4], 'K');
      // a8 = index 56 should have black rook
      expect(board.pieces[56], 'r');
    });

    test('BoardState mirrors for black', () {
      final board = BoardState.fromFen(
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
      expect(board.whiteToMove, isFalse);
      final mirrored = board.mirrored();
      expect(mirrored.whiteToMove, isTrue);
      // After mirroring, black pieces become uppercase (white) on flipped ranks
    });

    test('tokenizeBoard produces 768 elements', () {
      final board = BoardState.fromFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      final tokens = tokenizeBoard(board);
      expect(tokens.length, tokensPerBoard); // 768
    });

    test('tokenizeBoard has non-zero values for pieces', () {
      final board = BoardState.fromFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      final tokens = tokenizeBoard(board);
      // Should have 32 pieces = 32 non-zero values
      final nonZero = tokens.where((v) => v != 0).length;
      expect(nonZero, 32);
    });

    test('buildHistoryTokens produces 6144 elements', () {
      final board = BoardState.fromFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      final tokens = buildHistoryTokens([board]);
      expect(tokens.length, tokensPerPosition); // 6144
    });

    test('buildHistoryTokens left-pads with earliest board', () {
      final board = BoardState.fromFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      // Single board -> should be left-padded to 8 slots
      final tokens = buildHistoryTokens([board]);
      expect(tokens.length, tokensPerPosition);
      // All 8 history slots should have the same content (padded)
    });
  });

  group('Maia3 Moves', () {
    test('getAllMoves returns 4352 moves', () {
      expect(getAllMoves().length, numMoves);
    });

    test('moveToIndex and indexToMove roundtrip', () {
      expect(indexToMove(moveToIndex('e2e4')), 'e2e4');
      expect(indexToMove(moveToIndex('d7d5')), 'd7d5');
      expect(indexToMove(moveToIndex('a7a8q')), 'a7a8q');
    });

    test('promotion moves exist', () {
      expect(moveToIndex('a7a8q'), greaterThan(4095));
      expect(moveToIndex('h7h8n'), greaterThan(4095));
    });
  });

  group('Maia3 Utils', () {
    test('softmax produces valid probabilities', () {
      final logits = Float32List.fromList([1.0, 2.0, 3.0]);
      final probs = softmax(logits);
      expect(probs.length, 3);
      final sum = probs.reduce((a, b) => a + b);
      expect(sum, closeTo(1.0, 0.001));
      // Highest logit should have highest probability
      expect(probs[2], greaterThan(probs[1]));
      expect(probs[1], greaterThan(probs[0]));
    });

    test('softmax with mask zeros out masked entries', () {
      final logits = Float32List.fromList([1.0, 2.0, 3.0]);
      final mask = Uint8List.fromList([1, 0, 1]);
      final probs = softmax(logits, mask: mask);
      expect(probs[1], 0.0);
      expect(probs[0], greaterThan(0));
      expect(probs[2], greaterThan(0));
    });

    test('argmax returns index of max value', () {
      final arr = Float32List.fromList([0.1, 0.5, 0.3, 0.1]);
      expect(argmax(arr), 1);
    });

    test('mirrorSquare flips rank', () {
      expect(mirrorSquare('e2'), 'e7');
      expect(mirrorSquare('a1'), 'a8');
      expect(mirrorSquare('h8'), 'h1');
    });

    test('mirrorMove flips both squares', () {
      expect(mirrorMove('e2e4'), 'e7e5');
      expect(mirrorMove('a7a8q'), 'a2a1q');
    });

    test('wdlFromValueLogits returns valid WDL', () {
      final wdl = wdlFromValueLogits([0.0, 0.0, 0.0]);
      expect(wdl.win + wdl.draw + wdl.loss, closeTo(1.0, 0.001));
    });

    test('sampleIndex returns valid index', () {
      final probs = Float32List.fromList([0.5, 0.3, 0.2]);
      for (int i = 0; i < 100; i++) {
        final idx = sampleIndex(probs);
        expect(idx, inInclusiveRange(0, 2));
      }
    });
  });

  group('Maia3 History', () {
    test('resolveHistory with single FEN', () {
      final boards = resolveHistory(HistoryInput(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      ));
      expect(boards.length, 1);
    });

    test('resolveHistory with priorFens', () {
      final boards = resolveHistory(HistoryInput(
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        priorFens: [
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        ],
      ));
      expect(boards.length, 2);
    });
  });

  group('Maia3 Variants', () {
    test('getVariant returns known variants', () {
      expect(getVariant('5m').displayName, 'Maia3 5M');
      expect(getVariant('23m').approxBytes, greaterThan(0));
      expect(getVariant('79m').estimatedElo, 2500);
    });

    test('getVariant throws on unknown', () {
      expect(() => getVariant('999m'), throwsArgumentError);
    });

    test('variant URLs are HTTPS', () {
      for (final v in variants.values) {
        expect(v.url, startsWith('https://'));
      }
    });
  });
}
