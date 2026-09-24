// Tests for lib/vision/photo/: the chesscog-port board locator, its image
// operations, the square crops, the orientation guess and — when the trained
// models and the photo fixtures are present — the whole recognizer.
//
// Geometry tests draw their own boards; the photo fixtures in
// test/fixtures/board_photo/ are real photos under the MIT licence (see the
// NOTICE.txt there).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crispchess/vision/photo/board_locator.dart';
import 'package:crispchess/vision/photo/board_photo_recognizer.dart';
import 'package:crispchess/vision/photo/geometry.dart';
import 'package:crispchess/vision/photo/hough.dart';
import 'package:crispchess/vision/photo/image_ops.dart';
import 'package:crispchess/vision/photo/square_crops.dart';
import 'package:flutter_test/flutter_test.dart';

/// Board-square coordinates (0..8) -> image, for a board whose corners are
/// [tl], [tr], [br], [bl].
Float64List boardToImage(Pt tl, Pt tr, Pt br, Pt bl) => findHomography(
    const [Pt(0, 0), Pt(8, 0), Pt(8, 8), Pt(0, 8)], [tl, tr, br, bl])!;

/// A photo-like test image: noisy grey background, a wooden frame, and a
/// high-contrast 8x8 board in perspective. Returns the image.
RgbImage drawBoard(int w, int h, List<Pt> corners,
    {int seed = 1, bool lightOnEven = true}) {
  final m = boardToImage(corners[0], corners[1], corners[2], corners[3]);
  final inv = mat3Inv(m);
  final rnd = math.Random(seed);
  final data = Uint8List(w * h * 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = warpPoint(inv, x.toDouble(), y.toDouble());
      int r, g, b;
      if (p.x >= 0 && p.x < 8 && p.y >= 0 && p.y < 8) {
        final light = ((p.x.floor() + p.y.floor()).isEven) == lightOnEven;
        r = g = b = light ? 230 : 45;
      } else if (p.x >= -0.6 && p.x < 8.6 && p.y >= -0.6 && p.y < 8.6) {
        r = 150;
        g = 110;
        b = 70;
      } else {
        r = g = b = 128;
      }
      final n = rnd.nextInt(9) - 4;
      final o = (y * w + x) * 3;
      data[o] = (r + n).clamp(0, 255);
      data[o + 1] = (g + n).clamp(0, 255);
      data[o + 2] = (b + n).clamp(0, 255);
    }
  }
  return RgbImage(w, h, data);
}

double maxCornerError(List<Pt> a, List<Pt> b) {
  double m = 0;
  for (int i = 0; i < 4; i++) {
    m = math.max(m,
        math.sqrt(math.pow(a[i].x - b[i].x, 2) + math.pow(a[i].y - b[i].y, 2)));
  }
  return m;
}

void main() {
  group('image ops', () {
    test('greyscale uses OpenCV weights (and chesscog\'s R/B swap)', () {
      final img = RgbImage(2, 1, Uint8List.fromList([255, 0, 0, 0, 0, 255]));
      expect(img.toGray(swapRedBlue: false).px, [76, 29]);
      expect(img.toGray().px, [29, 76]);
    });

    test('Canny marks a vertical step edge one pixel wide', () {
      const w = 40, h = 30;
      final px = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 20; x < w; x++) {
          px[y * w + x] = 200;
        }
      }
      final e = canny(px, w, h, 90, 400);
      for (int y = 2; y < h - 2; y++) {
        final cols = [
          for (int x = 0; x < w; x++)
            if (e[y * w + x] != 0) x
        ];
        expect(cols.length, 1, reason: 'row $y: $cols');
        expect(cols.single, anyOf(19, 20));
      }
    });

    test('Canny hysteresis keeps weak edges only when joined to strong ones',
        () {
      const w = 60, h = 20;
      final px = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          // strong step at x = 15, weak step (35 grey levels) at x = 45
          px[y * w + x] = x >= 45 ? 235 : (x >= 15 ? 200 : 0);
        }
      }
      final e = canny(px, w, h, 90, 400);
      bool anyAt(int lo, int hi) {
        for (int y = 0; y < h; y++) {
          for (int x = lo; x < hi; x++) {
            if (e[y * w + x] != 0) return true;
          }
        }
        return false;
      }

      expect(anyAt(13, 17), isTrue);
      expect(anyAt(40, 50), isFalse); // 4 * 35 = 140 > low but never linked
    });

    test('warpPerspective with the identity copies the image', () {
      final src = Uint8List.fromList(List.generate(12, (i) => i * 20));
      final out = warpPerspective(src, 4, 3, 1,
          Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]), 4, 3);
      expect(out, src);
    });

    test('area resize averages 2x2 blocks', () {
      final src = Uint8List.fromList([0, 100, 50, 50, 200, 100, 50, 50]);
      final out = resizeBilinear(src, 4, 2, 2, 1, 1, antialias: true);
      expect(out, [100, 50]);
    });
  });

  group('geometry', () {
    test('findHomography recovers a perspective map from 4 and from N points',
        () {
      final h =
          Float64List.fromList([1.2, 0.1, 30, -0.05, 0.9, 12, 1e-4, 2e-4, 1]);
      final src = [
        for (int i = 0; i < 9; i++)
          for (int j = 0; j < 9; j++) Pt(i * 50.0, j * 40.0)
      ];
      final dst = [for (final p in src) warpPoint(h, p.x, p.y)];
      for (final n in [4, src.length]) {
        final idx = n == 4 ? [0, 8, 80, 72] : List.generate(n, (i) => i);
        final got = findHomography(
            [for (final i in idx) src[i]], [for (final i in idx) dst[i]])!;
        for (int k = 0; k < 9; k++) {
          expect(got[k], closeTo(h[k], 1e-6 + h[k].abs() * 1e-6),
              reason: 'n=$n k=$k');
        }
      }
    });

    test('least squares averages noisy correspondences', () {
      final rnd = math.Random(3);
      final h = Float64List.fromList([1, 0, 5, 0, 1, -3, 0, 0, 1]);
      final src = <Pt>[], dst = <Pt>[];
      for (int i = 0; i < 200; i++) {
        final p = Pt(rnd.nextDouble() * 500, rnd.nextDouble() * 500);
        final q = warpPoint(h, p.x, p.y);
        src.add(p);
        dst.add(Pt(q.x + rnd.nextDouble() - 0.5, q.y + rnd.nextDouble() - 0.5));
      }
      final got = findHomography(src, dst)!;
      final c = warpPoint(got, 250, 250);
      expect(c.x, closeTo(255, 0.2));
      expect(c.y, closeTo(247, 0.2));
    });

    test('inverse and corner sorting', () {
      final h = Float64List.fromList([2, 0.3, 1, 0.1, 1.5, -4, 1e-3, 0, 1]);
      final i = mat3Mul(h, mat3Inv(h));
      for (int k = 0; k < 9; k++) {
        expect(i[k], closeTo(k % 4 == 0 ? 1 : 0, 1e-12));
      }
      final s = sortCornerPoints(
          const [Pt(10, 90), Pt(90, 10), Pt(5, 8), Pt(95, 92)]);
      expect(s.map((p) => '${p.x.toInt()},${p.y.toInt()}').join(' '),
          '5,8 90,10 95,92 10,90');
    });
  });

  test('Hough finds drawn lines at the right rho and theta', () {
    const w = 300, h = 200;
    final e = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      e[y * w + 100] = 255; // x = 100: theta 0, rho 100
    }
    for (int x = 0; x < w; x++) {
      e[60 * w + x] = 255; // y = 60: theta 90 deg, rho 60
    }
    final lines = houghLines(e, w, h, 1, math.pi / 360, 150);
    expect(lines.length, greaterThanOrEqualTo(2));
    final top = lines.take(2).toList()
      ..sort((a, b) => a.theta.compareTo(b.theta));
    expect(top[0].rho, closeTo(100, 0.01));
    expect(top[0].theta, closeTo(0, 1e-6));
    expect(top[1].rho, closeTo(60, 0.01));
    expect(top[1].theta, closeTo(math.pi / 2, 1e-6));
  });

  group('locator', () {
    final cases = {
      'frontal': const [Pt(300, 150), Pt(900, 150), Pt(900, 750), Pt(300, 750)],
      'perspective': const [
        Pt(380, 180),
        Pt(840, 200),
        Pt(1010, 760),
        Pt(190, 740)
      ],
      'rotated 12 deg': const [
        Pt(420, 110),
        Pt(990, 230),
        Pt(870, 800),
        Pt(300, 680)
      ],
    };
    for (final MapEntry(key: name, value: truth) in cases.entries) {
      test('finds the board ($name) within 3 px', () {
        final img = drawBoard(1200, 900, truth);
        final r = locateBoard(img);
        expect(
            maxCornerError(r.corners, sortCornerPoints(truth)), lessThan(3.0),
            reason: '${r.corners} vs $truth; ${r.stats}');
      });
    }

    test('corners come back in the caller\'s pixels after the resize', () {
      const truth = [Pt(380, 180), Pt(840, 200), Pt(1010, 760), Pt(190, 740)];
      final small = drawBoard(1200, 900, truth);
      // Same scene at 2x: the locator shrinks it to 1200 wide and scales back.
      final big = RgbImage(
          2400, 1800, resizeBilinear(small.data, 1200, 900, 2400, 1800, 3));
      final r = locateBoard(big);
      final want = [
        for (final p in sortCornerPoints(truth)) Pt(p.x * 2, p.y * 2)
      ];
      expect(maxCornerError(r.corners, want), lessThan(8.0));
    });

    test('an image without a board is rejected', () {
      final rnd = math.Random(5);
      final img = RgbImage(
          1200,
          900,
          Uint8List.fromList(
              List.generate(1200 * 900 * 3, (_) => 100 + rnd.nextInt(20))));
      expect(() => locateBoard(img), throwsA(isA<BoardNotLocatedException>()));
    });
  });

  group('crops', () {
    // A warped board whose pixels encode their own coordinates.
    RgbImage coordImage(int size) {
      final d = Uint8List(size * size * 3);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final o = (y * size + x) * 3;
          d[o] = x ~/ 4;
          d[o + 1] = y ~/ 4;
          d[o + 2] = 255;
        }
      }
      return RgbImage(size, size, d);
    }

    test('occupancy crop is the square plus half a square each side', () {
      final w = coordImage(500);
      final c = occupancyCrop(w, 2, 3); // x from 175, y from 125
      expect(c[0], 175 ~/ 4);
      expect(c[1], 125 ~/ 4);
      const last = (99 * 100 + 99) * 3;
      expect(c[last], 274 ~/ 4);
      expect(c[last + 1], 224 ~/ 4);
    });

    test('piece crops: tall for near rows, mirrored on the left half', () {
      final w = coordImage(800);
      // Right half, row 7 (nearest): x1 = 200 + 50*6 = 500, x2 = 200 + 50*(7 + .25)
      final right = pieceCrop(w, 7, 6);
      const bottomLeft = ((199) * 100 + 0) * 3;
      expect(right[bottomLeft], 500 ~/ 4);
      expect(right[bottomLeft + 1], 599 ~/ 4); // y2 - 1 = 200 + 400 - 1
      // Height: 1 + 0 squares above -> 100 px; the rest is black padding.
      expect(right[(99 * 100) * 3 + 2], 0);
      expect(right[(100 * 100) * 3 + 2], 255);
      // Left half, row 0 (farthest): 3 squares above, mirrored: first column
      // of the crop is the square's right edge.
      final left = pieceCrop(w, 0, 1);
      final x2 = (200 + 50 * (1 + 1)).toInt();
      expect(left[(199 * 100) * 3], (x2 - 1) ~/ 4);
      expect(left[2], 255); // full 200 px height used
    });

    test('warp maps the corners onto the square grid', () {
      const truth = [Pt(380, 180), Pt(840, 200), Pt(1010, 760), Pt(190, 740)];
      final img = drawBoard(1200, 900, truth);
      final w = warpForOccupancy(img, truth);
      // Centre of a8-ish cell (0,0) is light (even), (0,1) dark.
      int grey(int x, int y) => w.data[(y * 500 + x) * 3];
      expect(grey(75, 75), greaterThan(180));
      expect(grey(125, 75), lessThan(90));
      expect(grey(425, 425), greaterThan(180));
    });
  });

  group('orientation', () {
    List<double> tones({required bool lightEven}) => [
          for (int i = 0; i < 64; i++)
            ((i ~/ 8 + i % 8).isEven == lightEven) ? 200.0 : 60.0
        ];

    const start =
        'rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR';

    List<String> gridFor(String chess, int rot) {
      final g = List.filled(64, '.');
      for (int i = 0; i < 64; i++) {
        g[BoardPhotoResult.gridIndexFor(i, rot)] = chess[i];
      }
      return g;
    }

    for (int rot = 0; rot < 4; rot++) {
      test('recovers rotation $rot from colours and piece sides', () {
        final grid = gridFor(start, rot);
        final pOcc = [for (final p in grid) p == '.' ? 0.0 : 1.0];
        final (got, conf) =
            guessRotation(grid, tones(lightEven: rot.isEven), pOcc);
        expect(got, rot);
        expect(conf, greaterThan(0.5));
        final res = BoardPhotoResult.fromGrid(grid, rotation: got);
        expect(res.placement, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');
        expect(res.rotated(4).placement, res.placement);
        expect(res.rotated(2).placement,
            'RNBKQBNR/PPPPPPPP/8/8/8/8/pppppppp/rnbkqbnr');
      });
    }
  });

  test('rules: one king each, no back-rank pawns, at most eight pawns', () {
    const k = 12;
    int cls(String p) => photoPieceClasses.indexOf(p);
    final probs = Float64List(64 * k);
    final pOcc = List<double>.filled(64, 0);
    void put(int cell, Map<String, double> p) {
      pOcc[cell] = 0.99;
      for (final e in p.entries) {
        probs[cell * k + cls(e.key)] = e.value;
      }
    }

    // Grid = chess view (rotation 0): cell 0 = a8, cell 63 = h1.
    put(60, {'K': 0.9, 'Q': 0.1}); // e1: the real white king
    put(59, {'K': 0.6, 'Q': 0.4}); // d1: a second "king" -> queen
    put(4, {'q': 0.55, 'k': 0.45}); // e8: black king read as a queen
    put(0, {'p': 0.7, 'r': 0.3}); // a8: pawn on the back rank -> rook
    for (int f = 0; f < 8; f++) {
      put(48 + f, {'P': 0.95, 'B': 0.05}); // eight white pawns on rank 2
    }
    put(35, {'P': 0.6, 'B': 0.4}); // a ninth, least sure -> bishop
    final (raw, _) = decodePhotoGrid(pOcc, probs, 0, rules: false);
    expect(
        [raw[60], raw[59], raw[4], raw[0], raw[35]], ['K', 'K', 'q', 'p', 'P']);
    final (g, conf) = decodePhotoGrid(pOcc, probs, 0);
    expect([g[60], g[59], g[4], g[0], g[35]], ['K', 'Q', 'k', 'r', 'B']);
    expect(conf[59], closeTo(0.99 * 0.4, 1e-9));
    // Seen from Black's side the back ranks are the same rows, turned.
    final (g2, _) = decodePhotoGrid(pOcc, probs, 2);
    expect(g2[0], 'r');
  });

  group('end to end on real photos', () {
    final models = _findModels();
    final fixtures = Directory('test/fixtures/board_photo');
    final labelled = fixtures.existsSync()
        ? (fixtures
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    testWidgets('recognises the fixture photos', (tester) async {
      await tester.runAsync(() async {
        final rec = BoardPhotoRecognizer(models!, backend: PhotoBackend.dart);
        int exact = 0, squares = 0;
        for (final f in labelled) {
          // name: <placement with - for />__<anything>.jpg
          final want =
              f.uri.pathSegments.last.split('__').first.replaceAll('-', '/');
          final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
          final image = (await codec.getNextFrame()).image;
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final r = await rec.recognize(
              bytes.buffer.asUint8List(), image.width, image.height);
          final got = r.squares;
          final wantSq = _expand(want);
          int ok = 0;
          for (int i = 0; i < 64; i++) {
            if (got[i] == wantSq[i]) ok++;
          }
          squares += ok;
          if (ok == 64) exact++;
          // ignore: avoid_print
          print('${f.uri.pathSegments.last}: $ok/64 rot=${r.rotation} '
              '${r.placement} ${r.timings}');
        }
        rec.dispose();
        // Loose floors: this guards the plumbing (orientation, crops, class
        // order), not the model's accuracy, which tool/board_photo measures.
        expect(squares / (64 * labelled.length), greaterThan(0.9));
        expect(exact, greaterThanOrEqualTo(labelled.length ~/ 2));
      });
    },
        skip: models == null || labelled.isEmpty,
        timeout: const Timeout(Duration(minutes: 10)));
  });
}

List<String> _expand(String placement) => [
      for (final ch in placement.replaceAll('/', '').split(''))
        ...(int.tryParse(ch) != null ? List.filled(int.parse(ch), '.') : [ch])
    ];

BoardPhotoModels? _findModels() {
  // The models are downloaded by the app, not in the repo: point
  // BOARD_PHOTO_MODELS at a folder holding them to run these checks.
  for (final dir in [
    if (Platform.environment['BOARD_PHOTO_MODELS'] case final d?) d,
    'tool/board_photo/models',
  ]) {
    final o = File('$dir/board_photo_occupancy.onnx');
    final p = File('$dir/board_photo_pieces.onnx');
    if (o.existsSync() && p.existsSync()) {
      return BoardPhotoModels(
          occupancy: o.readAsBytesSync(), pieces: p.readAsBytesSync());
    }
  }
  return null;
}
