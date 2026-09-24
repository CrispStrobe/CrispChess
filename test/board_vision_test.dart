import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crispchess/vision/board_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures come from tool/board_vision/make_fixtures.py: a screen capture
/// with coordinates, a hatched print diagram in a frame, a board seen from
/// Black's side, a board inside a mock app screenshot, a small print diagram
/// scanned low and zoomed, a slightly rotated and skewed photo of a screen,
/// and a board pasted over another diagram.
const _fixtures = 'test/fixtures/board_vision';

Future<(Uint8List, int, int)> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return (data!.buffer.asUint8List(), image.width, image.height);
}

void main() {
  final expected =
      (jsonDecode(File('$_fixtures/expected.json').readAsStringSync()) as Map)
          .cast<String, dynamic>();

  late BoardRecognizer recognizer;
  setUpAll(() {
    recognizer = BoardRecognizer(
        File('assets/models/board_squares.onnx').readAsBytesSync());
  });
  tearDownAll(() => recognizer.dispose());

  for (final entry in expected.entries) {
    testWidgets('recognizes ${entry.key}', (tester) async {
      await tester.runAsync(() async {
        final (rgba, w, h) = await _decode('$_fixtures/${entry.key}.png');
        final result = await recognizer.recognize(rgba, w, h);
        final want = entry.value as Map;
        expect(result.placement, want['placement'],
            reason: 'board found at ${result.rect}; uncertain: '
                '${result.uncertainSquares().map(BoardRecognition.squareName)}');
        expect(result.flipped, want['flipped']);
        expect(result.problems, isEmpty);
      });
    });
  }

  testWidgets('a given crop overrides detection', (tester) async {
    await tester.runAsync(() async {
      // screen_chessnut: 48 px squares after a 14 px margin.
      final (rgba, w, h) = await _decode('$_fixtures/screen_chessnut.png');
      final result = await recognizer.recognize(rgba, w, h,
          crop: const BoardRect(14, 14, 384, 384));
      expect(result.placement, expected['screen_chessnut']['placement']);
    });
  });

  testWidgets('detection lands on the board grid', (tester) async {
    await tester.runAsync(() async {
      // Geometry alone, independent of the classifier.
      final (rgba, w, h) = await _decode('$_fixtures/screen_chessnut.png');
      final rect = locateBoard(rgba, w, h)!;
      expect(rect.left, closeTo(14, 2));
      expect(rect.top, closeTo(14, 2));
      expect(rect.width, closeTo(384, 3));
      expect(rect.height, closeTo(384, 3));
    });
  });

  testWidgets('a lattice one square off is moved onto the board',
      (tester) async {
    await tester.runAsync(() async {
      // two_diagrams: the back diagram's visible file continues the front
      // board's lattice one square to the left.
      final (rgba, w, h) = await _decode('$_fixtures/two_diagrams.png');
      final rect = locateBoard(rgba, w, h)!;
      expect(rect.left, closeTo(33, 2));
      expect(rect.top, closeTo(7, 2));
      expect(rect.width, closeTo(208, 3));
    });
  });

  // parity.json holds what tool/board_vision/render.py's cell_to_input makes
  // of a few cells — the network was trained on exactly that, so Dart must
  // compute the same.
  final parity =
      (jsonDecode(File('$_fixtures/parity.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
  for (final p in parity) {
    testWidgets('cell input matches the trainer: ${p['fixture']} ${p['rect']}',
        (tester) async {
      await tester.runAsync(() async {
        final (rgba, w, h) = await _decode('$_fixtures/${p['fixture']}.png');
        final gray = GrayImage.fromRgba(rgba, w, h);
        final r = (p['rect'] as List).cast<num>();
        final cell = Float32List(boardSquareInput * boardSquareInput);
        cellInput(gray, r[0].toDouble(), r[1].toDouble(), r[2].toDouble(),
            r[3].toDouble(), cell, 0);
        double sum = 0, sq = 0;
        for (final v in cell) {
          sum += v;
          sq += v * v;
        }
        expect(sum, closeTo(p['sum'] as num, 1e-3));
        expect(sq, closeTo(p['sumSq'] as num, 1e-3));
        for (final s in (p['samples'] as List).cast<List>()) {
          expect(cell[(s[0] as int) * boardSquareInput + (s[1] as int)],
              closeTo(s[2] as num, 1e-6));
        }
      });
    });
  }

  test('transparent pixels read as white paper', () {
    // Premultiplied RGBA: black ink, half-covered ink, fully transparent.
    final g = GrayImage.fromRgba(
        Uint8List.fromList([0, 0, 0, 255, 0, 0, 0, 128, 0, 0, 0, 0]), 3, 1);
    expect(g.pixels, [0, 127, 255]);
  });

  test('an image with no grid is not a board', () {
    const w = 320, h = 240;
    final rgba = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        rgba[i] = (x * 255 ~/ w);
        rgba[i + 1] = (y * 255 ~/ h);
        rgba[i + 2] = 128;
        rgba[i + 3] = 255;
      }
    }
    expect(locateBoard(rgba, w, h), isNull);
  });

  group('orientation and sanity', () {
    List<String> squares(String placement) => [
          for (final ch in placement.replaceAll('/', '').split(''))
            ...(int.tryParse(ch) != null
                ? List.filled(int.parse(ch), '.')
                : [ch]),
        ];

    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';

    test('the start position is read as upright', () {
      expect(looksFlipped(squares(start)), isFalse);
    });

    test('the start position seen from Black is flipped', () {
      expect(looksFlipped(squares(start).reversed.toList()), isTrue);
    });

    test('rotated() turns the placement 180 degrees', () {
      final r = BoardRecognition(
        rect: const BoardRect(0, 0, 8, 8),
        squares: squares(start),
        confidence: List.filled(64, 1),
        flipped: false,
      );
      expect(
          r.rotated().placement, 'RNBKQBNR/PPPPPPPP/8/8/8/8/pppppppp/rnbkqbnr');
      expect(r.rotated().rotated().placement, start);
    });

    Float64List probs(Map<int, Map<String, double>> overrides) {
      // Every square confidently empty unless overridden.
      final k = boardSquareClasses.length;
      final p = Float64List(64 * k);
      for (int i = 0; i < 64; i++) {
        final o = overrides[i] ?? {'.': 1.0};
        o.forEach((c, v) => p[i * k + boardSquareClasses.indexOf(c)] = v);
      }
      return p;
    }

    String decoded(Float64List p) {
      final c = decodeSquares(p);
      return BoardRecognition(
        rect: const BoardRect(0, 0, 8, 8),
        squares: [for (final i in c) boardSquareClasses[i]],
        confidence: List.filled(64, 1),
        flipped: false,
      ).placement;
    }

    test('decoding keeps pawns off the back ranks', () {
      expect(
          decoded(probs({
            0: {'p': 0.6, 'b': 0.3, '.': 0.1},
            4: {'k': 0.9, '.': 0.1},
            60: {'K': 0.9, '.': 0.1},
            63: {'P': 0.5, '.': 0.4, 'Q': 0.1},
          })),
          'b3k3/8/8/8/8/8/8/4K3');
    });

    test('decoding keeps one king per colour, the likeliest', () {
      expect(
          decoded(probs({
            4: {'k': 0.9, '.': 0.1},
            12: {'k': 0.5, 'q': 0.4, '.': 0.1},
            60: {'K': 0.9, '.': 0.1},
          })),
          '4k3/4q3/8/8/8/8/8/4K3');
    });

    test('decoding restores a missed king only on real evidence', () {
      expect(
          decoded(probs({
            4: {'k': 0.9, '.': 0.1},
            60: {'Q': 0.6, 'K': 0.35, '.': 0.05},
          })),
          '4k3/8/8/8/8/8/8/4K3');
      // A diagram without kings stays without them.
      expect(
          decoded(probs({
            10: {'R': 0.95, 'K': 0.05},
          })),
          '8/2R5/8/8/8/8/8/8');
    });

    test('problems name impossible placements', () {
      final r = BoardRecognition(
        rect: const BoardRect(0, 0, 8, 8),
        squares: squares('P7/8/8/8/8/8/8/K6K'),
        confidence: [...List.filled(63, 1.0), 0.3],
        flipped: false,
      );
      expect(r.problems,
          containsAll(['whiteKings:2', 'blackKings:0', 'pawnOnBackRank:a8']));
      expect(r.uncertainSquares(), [63]);
    });
  });
}
