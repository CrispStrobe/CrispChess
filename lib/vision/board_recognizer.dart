/// Board image → FEN piece placement, fully offline.
///
/// A picture of a chessboard (a screenshot, a scanned book diagram) is
/// located, cut into its 64 squares, and each square is classified by a small
/// CNN (assets/models/board_squares.onnx, trained by tool/board_vision/) run
/// through the pure-Dart ONNX interpreter — the same one Maia3 uses — so it
/// works on every platform, the web included, with no native code.
///
/// Input is raw RGBA pixels, not an encoded image: decoding belongs to the
/// caller (`dart:ui` in the app, a fixture reader in tests), which keeps this
/// file free of Flutter and testable in plain Dart.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Network output classes, in output order. `.` is an empty square; the rest
/// are FEN piece letters. Must match `CLASSES` in tool/board_vision/render.py.
const List<String> boardSquareClasses = [
  '.', 'P', 'N', 'B', 'R', 'Q', 'K', 'p', 'n', 'b', 'r', 'q', 'k', //
];

/// Side of the square crop the network takes.
const int boardSquareInput = 32;

/// Where the board sits in the image, in source pixels.
class BoardRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const BoardRect(this.left, this.top, this.width, this.height);

  double get right => left + width;
  double get bottom => top + height;

  @override
  String toString() =>
      'BoardRect(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)} x ${height.toStringAsFixed(1)})';
}

/// A grayscale image on 0..255, with a summed-area table for box averages.
class GrayImage {
  final int width;
  final int height;

  /// Row-major luminance, 0..255.
  final Int32List pixels;

  GrayImage(this.width, this.height, this.pixels);

  /// Luminance `(299 R + 587 G + 114 B) / 1000`, integer division — the exact
  /// formula the training data was made with.
  ///
  /// [rgba] has premultiplied alpha (what `dart:ui`'s `rawRgba` gives):
  /// translucent pixels are composited over white, so a diagram with a
  /// transparent background reads as ink on paper, not on black. Opaque
  /// pixels are unaffected.
  factory GrayImage.fromRgba(Uint8List rgba, int width, int height) {
    if (rgba.length < width * height * 4) {
      throw ArgumentError(
          'RGBA buffer holds fewer than $width x $height pixels');
    }
    final px = Int32List(width * height);
    for (int i = 0, j = 0; i < px.length; i++, j += 4) {
      final v = (299 * rgba[j] + 587 * rgba[j + 1] + 114 * rgba[j + 2]) ~/ 1000;
      final a = rgba[j + 3];
      px[i] = a == 255 ? v : math.min(255, v + 255 - a);
    }
    return GrayImage(width, height, px);
  }

  Float64List? _integral;

  /// Summed-area table, (width+1) x (height+1).
  Float64List get integral {
    final cached = _integral;
    if (cached != null) return cached;
    final w1 = width + 1;
    final ii = Float64List(w1 * (height + 1));
    for (int y = 0; y < height; y++) {
      double row = 0;
      for (int x = 0; x < width; x++) {
        row += pixels[y * width + x];
        ii[(y + 1) * w1 + x + 1] = ii[y * w1 + x + 1] + row;
      }
    }
    return _integral = ii;
  }

  double _boxSum(int xa, int ya, int xb, int yb) {
    final ii = integral;
    final w1 = width + 1;
    return ii[yb * w1 + xb] -
        ii[ya * w1 + xb] -
        ii[yb * w1 + xa] +
        ii[ya * w1 + xa];
  }

  /// Box-downscale by an integer [factor].
  GrayImage downscale(int factor) {
    if (factor <= 1) return this;
    final w = width ~/ factor, h = height ~/ factor;
    final px = Int32List(w * h);
    final area = factor * factor;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        px[y * w + x] = (_boxSum(x * factor, y * factor, (x + 1) * factor,
                    (y + 1) * factor) /
                area)
            .round();
      }
    }
    return GrayImage(w, h, px);
  }
}

/// The half-open pixel ranges an extent is split into — mirrors `_bounds` in
/// tool/board_vision/render.py.
List<(int, int)> _bounds(double start, double extent, int n, int limit) {
  final out = <(int, int)>[];
  for (int k = 0; k < n; k++) {
    int a = (start + k * extent / n).floor();
    int b = (start + (k + 1) * extent / n).floor();
    a = a.clamp(0, limit - 1);
    b = b.clamp(a + 1, limit);
    out.add((a, b));
  }
  return out;
}

/// Area-average one cell to 32x32 in [0, 1], written into [out] at [offset].
///
/// The preprocessing contract with the training script: see
/// `cell_to_input` in tool/board_vision/render.py.
void cellInput(GrayImage img, double x0, double y0, double w, double h,
    Float32List out, int offset) {
  final xs = _bounds(x0, w, boardSquareInput, img.width);
  final ys = _bounds(y0, h, boardSquareInput, img.height);
  for (int i = 0; i < boardSquareInput; i++) {
    final (ya, yb) = ys[i];
    for (int j = 0; j < boardSquareInput; j++) {
      final (xa, xb) = xs[j];
      final mean = img._boxSum(xa, ya, xb, yb) / ((yb - ya) * (xb - xa));
      out[offset + i * boardSquareInput + j] = (mean / 255.0).toDouble();
    }
  }
}

/// Result of recognizing one board.
class BoardRecognition {
  /// Where the board was found (or the crop that was given).
  final BoardRect rect;

  /// 64 FEN letters (`.` = empty), a8..h8, a7..h7, …, a1..h1 — already
  /// turned to White's point of view when [flipped].
  final List<String> squares;

  /// Network confidence (softmax probability of the chosen class) per square,
  /// same order as [squares].
  final List<double> confidence;

  /// The image showed the board from Black's side and was turned around.
  final bool flipped;

  const BoardRecognition({
    required this.rect,
    required this.squares,
    required this.confidence,
    required this.flipped,
  });

  /// The same recognition seen the other way round — for a UI "flip" button
  /// when the orientation guess was wrong.
  BoardRecognition rotated() => BoardRecognition(
        rect: rect,
        squares: squares.reversed.toList(),
        confidence: confidence.reversed.toList(),
        flipped: !flipped,
      );

  /// The FEN piece-placement field.
  String get placement {
    final rows = <String>[];
    for (int r = 0; r < 8; r++) {
      final sb = StringBuffer();
      int run = 0;
      for (int c = 0; c < 8; c++) {
        final p = squares[r * 8 + c];
        if (p == '.') {
          run++;
        } else {
          if (run > 0) sb.write(run);
          run = 0;
          sb.write(p);
        }
      }
      if (run > 0) sb.write(run);
      rows.add(sb.toString());
    }
    return rows.join('/');
  }

  /// Algebraic name of square index [i] in [squares] order (0 = a8).
  static String squareName(int i) =>
      '${String.fromCharCode(97 + i % 8)}${8 - i ~/ 8}';

  /// Indices of squares the network was unsure about — highlight these.
  List<int> uncertainSquares({double threshold = 0.6}) => [
        for (int i = 0; i < 64; i++)
          if (confidence[i] < threshold) i,
      ];

  /// Reasons the placement cannot be a legal position; empty when it passes.
  /// Codes, not prose, so the UI can localise them: `whiteKings:N`,
  /// `blackKings:N`, `pawnOnBackRank:<square>`, `whitePawns:N`,
  /// `blackPawns:N`.
  List<String> get problems {
    final out = <String>[];
    int count(String p) => squares.where((s) => s == p).length;
    final wk = count('K'), bk = count('k');
    if (wk != 1) out.add('whiteKings:$wk');
    if (bk != 1) out.add('blackKings:$bk');
    for (int i = 0; i < 64; i++) {
      final rank = 8 - i ~/ 8;
      if ((rank == 1 || rank == 8) &&
          (squares[i] == 'P' || squares[i] == 'p')) {
        out.add('pawnOnBackRank:${squareName(i)}');
      }
    }
    final wp = count('P'), bp = count('p');
    if (wp > 8) out.add('whitePawns:$wp');
    if (bp > 8) out.add('blackPawns:$bp');
    return out;
  }
}

/// Recognizes chessboards in images with the bundled square classifier.
class BoardRecognizer {
  final OnnxModel _model;

  /// [modelBytes] are the bytes of assets/models/board_squares.onnx.
  BoardRecognizer(Uint8List modelBytes)
      : _model = OnnxModel.fromBytes(modelBytes);

  /// Find the board in [rgba] (or use [crop]), classify its squares, and
  /// guess the orientation.
  ///
  /// Throws [BoardNotFoundException] when no board-like 8x8 grid is found and
  /// no [crop] was given — the UI should then let the user frame it.
  Future<BoardRecognition> recognize(Uint8List rgba, int width, int height,
      {BoardRect? crop}) async {
    final gray = GrayImage.fromRgba(rgba, width, height);
    final rect = crop ?? locateBoardGray(gray);
    if (rect == null) throw const BoardNotFoundException();

    const n = boardSquareInput * boardSquareInput;
    final input = Float32List(64 * n);
    final cw = rect.width / 8, ch = rect.height / 8;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        cellInput(gray, rect.left + c * cw, rect.top + r * ch, cw, ch, input,
            (r * 8 + c) * n);
      }
    }
    final out = await _model.runAsync({
      'input': Tensor.float(input, [64, 1, boardSquareInput, boardSquareInput]),
    }, [
      'logits'
    ]);
    final logits = out['logits']!.asFloatList();
    final k = boardSquareClasses.length;
    final probs = Float64List(64 * k);
    for (int i = 0; i < 64; i++) {
      double mx = -double.infinity;
      for (int j = 0; j < k; j++) {
        mx = math.max(mx, logits[i * k + j]);
      }
      double sum = 0;
      for (int j = 0; j < k; j++) {
        sum += probs[i * k + j] = math.exp(logits[i * k + j] - mx);
      }
      for (int j = 0; j < k; j++) {
        probs[i * k + j] /= sum;
      }
    }
    final choice = decodeSquares(probs);
    final squares = [for (final c in choice) boardSquareClasses[c]];
    final conf = [for (int i = 0; i < 64; i++) probs[i * k + choice[i]]];
    final asSeen = BoardRecognition(
        rect: rect, squares: squares, confidence: conf, flipped: false);
    return looksFlipped(squares) ? asSeen.rotated() : asSeen;
  }

  void dispose() => _model.dispose();
}

/// The class of each square from per-square probabilities ([probs] is
/// 64 x 13, row-major, squares in image order), with the rules a diagram
/// can be relied on to follow applied where the network is unsure:
///
/// - no pawn on the top or bottom row (a back rank from either side): the
///   best non-pawn class instead;
/// - at most one king per colour: the likeliest keeps it, any other takes
///   its next-best class;
/// - a king the network missed is put on the square likeliest to hold it,
///   when some square gives it at least [missingKing] — a diagram may leave
///   the kings out (a study fragment), so weaker evidence is left alone.
List<int> decodeSquares(Float64List probs, {double missingKing = 0.1}) {
  final k = boardSquareClasses.length;
  final pawns = {
    boardSquareClasses.indexOf('P'),
    boardSquareClasses.indexOf('p'),
  };
  int best(int i, Set<int> not) {
    int arg = -1;
    for (int j = 0; j < k; j++) {
      if (not.contains(j)) continue;
      if (arg < 0 || probs[i * k + j] > probs[i * k + arg]) arg = j;
    }
    return arg;
  }

  final banned =
      List.generate(64, (i) => i < 8 || i >= 56 ? {...pawns} : <int>{});
  final out = [for (int i = 0; i < 64; i++) best(i, banned[i])];
  for (final king in [
    boardSquareClasses.indexOf('K'),
    boardSquareClasses.indexOf('k')
  ]) {
    final holders = [
      for (int i = 0; i < 64; i++)
        if (out[i] == king) i
    ];
    if (holders.length > 1) {
      holders
          .sort((a, b) => probs[b * k + king].compareTo(probs[a * k + king]));
      for (final i in holders.skip(1)) {
        banned[i].add(king);
        out[i] = best(i, banned[i]);
      }
    } else if (holders.isEmpty) {
      int arg = -1;
      for (int i = 0; i < 64; i++) {
        // Never take the other king's square.
        if (out[i] == boardSquareClasses.indexOf('K') ||
            out[i] == boardSquareClasses.indexOf('k')) {
          continue;
        }
        if (arg < 0 || probs[i * k + king] > probs[arg * k + king]) arg = i;
      }
      if (arg >= 0 && probs[arg * k + king] >= missingKing) out[arg] = king;
    }
  }
  return out;
}

class BoardNotFoundException implements Exception {
  const BoardNotFoundException();
  @override
  String toString() => 'No chessboard found in the image';
}

/// Whether a placement read top-to-bottom looks like it is seen from Black's
/// side: White's king in the top half and Black's in the bottom, and White's
/// pawns standing above Black's. Each clue votes; no clue means "not flipped".
bool looksFlipped(List<String> squares) {
  int vote = 0;
  final wk = squares.indexOf('K'), bk = squares.indexOf('k');
  if (wk >= 0) vote += wk ~/ 8 < 4 ? 1 : -1;
  if (bk >= 0) vote += bk ~/ 8 >= 4 ? 1 : -1;
  double meanRow(String p) {
    final rows = [
      for (int i = 0; i < 64; i++)
        if (squares[i] == p) i ~/ 8
    ];
    return rows.isEmpty
        ? double.nan
        : rows.reduce((a, b) => a + b) / rows.length;
  }

  final wp = meanRow('P'), bp = meanRow('p');
  if (!wp.isNaN && !bp.isNaN && wp != bp) vote += wp < bp ? 2 : -2;
  return vote > 0;
}

/// Locate the board in an RGBA image. Null when nothing grid-like is found.
BoardRect? locateBoard(Uint8List rgba, int width, int height) =>
    locateBoardGray(GrayImage.fromRgba(rgba, width, height));

/// Locate an 8x8 board by its lattice of square edges.
///
/// Neighbouring squares always differ in colour, so each of the seven inner
/// grid lines is a full-length edge: summed down the columns, the edge
/// strength peaks at seven equally spaced positions (rows likewise). Fitting
/// that lattice on a coarse copy, then refining at full resolution, finds the
/// board inside screenshots with UI around it and book diagrams with frames.
///
/// Edges are measured as the difference of the mean brightness on either
/// side over a few pixels, not a one-pixel gradient: hatched or stippled dark
/// squares in printed diagrams are all texture, which a one-pixel gradient
/// sees everywhere, while the two side means over a hatched area agree.
BoardRect? locateBoardGray(GrayImage full) {
  final factor = math.max(1, (math.max(full.width, full.height) / 400).ceil());
  final small = full.downscale(factor);
  if (small.width < 32 || small.height < 32) return null;

  // Upright first. A board photographed or scanned slightly turned smears
  // its lines across the profile; only when the upright search finds
  // nothing are sheared profiles tried, about 1 and 2 degrees each way.
  var coarse = _coarseFit(small, 0);
  if (coarse == null || coarse.weak) {
    for (final deg in const [1.0, -1.0, 2.0, -2.0]) {
      final c = _coarseFit(small, math.tan(deg * math.pi / 180));
      if (c != null && (coarse == null || c.quality > coarse.quality)) {
        coarse = c;
      }
    }
  }
  if (coarse == null) return null;
  final (lx, ly, skew) = (coarse.x, coarse.y, coarse.skew);

  // Refine at full resolution around the coarse answer.
  final f = factor.toDouble();
  var gx = _refine(full, lx, f,
      vertical: true,
      spanOther: (ly.start * f, (ly.start + 8 * ly.step) * f),
      skew: skew);
  var gy = _refine(full, ly, f,
      vertical: false,
      spanOther: (gx.start, gx.start + 8 * gx.step),
      skew: skew);

  // A lattice one square off still has seven strong lines when a frame,
  // coordinates, a neighbouring diagram or a UI panel supplies the eighth.
  // The squares tell them apart: on the true 8x8 every row and column
  // alternates between the two square tones.
  final (dx, dy) = _checkerShift(full, gx, gy, skew);
  if (dx != 0 || dy != 0) {
    gx = _refine(
        full, _Lattice(gx.start + dx * gx.step, gx.step, gx.contrast), 1,
        vertical: true,
        spanOther: (gy.start + dy * gy.step, gy.start + (dy + 8) * gy.step),
        skew: skew);
    gy = _refine(
        full, _Lattice(gy.start + dy * gy.step, gy.step, gy.contrast), 1,
        vertical: false,
        spanOther: (gx.start, gx.start + 8 * gx.step),
        skew: skew);
  }
  // Faint lines are a board only if its squares alternate like one. (Not
  // asked of strong lattices: some real boards alternate too little in the
  // square corners this measures to be judged by it.)
  if (coarse.weak) {
    final alt = _checkerScore(full, gx.start, gy.start, gx.step, gy.step, skew);
    if (alt == null || alt < _weakAlternation) return null;
  }
  // A turned board as the axis-aligned rect through its centre — what the
  // classifier was trained to read.
  final (left, top) =
      _unshear(full, gx.start + 4 * gx.step, gy.start + 4 * gy.step, skew);
  return BoardRect(
      left - 4 * gx.step, top - 4 * gy.step, gx.step * 8, gy.step * 8);
}

/// Image position of the point at (x', y') in sheared-profile coordinates:
/// columns were straightened by x' = x − (y − H/2)·skew, rows by
/// y' = y + (x − W/2)·skew (a small turn moves both ways at once).
(double, double) _unshear(GrayImage img, double xs, double ys, double skew) {
  if (skew == 0) return (xs, ys);
  // Solve x = xs + (y − H/2)·skew, y = ys − (x − W/2)·skew.
  final hc = img.height / 2, wc = img.width / 2;
  final k = skew * skew;
  final x = (xs + (ys - hc + wc * skew) * skew) / (1 + k);
  final y = ys - (x - wc) * skew;
  return (x, y);
}

class _Coarse {
  final _Lattice x, y;
  final double skew;

  /// Lattice lines too faint to be sure of on their own.
  final bool weak;
  _Coarse(this.x, this.y, this.skew, {this.weak = false});

  /// Strong beats weak, then the clearer lattice wins.
  double get quality => math.min(x.contrast, y.contrast) + (weak ? 0 : 100);
}

/// The coarse lattice pair on [small] with profiles sheared by [skew]
/// (tan of the turn), or null when nothing board-like is there.
_Coarse? _coarseFit(GrayImage small, double skew) {
  // Alternate the two axes, each time restricting the profile to the
  // span the other axis found, so text and UI outside the board fade out.
  var xr = (0, small.width);
  var yr = (0, small.height);
  _Lattice? lx, ly;
  for (int it = 0; it < 3; it++) {
    final px = _profile(small,
        vertical: true,
        from: yr.$1,
        to: yr.$2,
        r: 3,
        cap: _edgeCap,
        skew: skew);
    lx = _searchNear(px, lx, small.width);
    if (lx == null) return null;
    xr = lx.span(small.width);
    final py = _profile(small,
        vertical: false,
        from: xr.$1,
        to: xr.$2,
        r: 3,
        cap: _edgeCap,
        skew: skew);
    ly = ly == null
        // Squares are about square: the first row search looks only at
        // steps near the column step, so a block of text lines (whose
        // pitch is anything) cannot stand in for the rows.
        ? _fitLattice(py,
            minStep: lx.step / _maxAspect,
            maxStep: lx.step * _maxAspect,
            stepInc: 0.25)
        : _searchNear(py, ly, small.height);
    if (ly == null) return null;
    yr = ly.span(small.height);
  }
  final cx = lx!, cy = ly!;
  // A board's squares are square; a lattice pair far from that is some
  // other grid (a table, a keyboard).
  final ratio = cx.step / cy.step;
  if (ratio < 1 / _maxAspect || ratio > _maxAspect) return null;
  // Beyond 5:4 only for a lattice that is unmistakable in both directions:
  // a picture stretched by a camera app or a screen, not a table.
  if ((ratio < 0.8 || ratio > 1.25) &&
      (cx.contrast < 2.5 || cy.contrast < 2.5)) {
    return null;
  }
  if (cx.convincing && cy.convincing) return _Coarse(cx, cy, skew);
  // Faint lines in a busy picture (a dithered or noisy scan): kept, but
  // only as a candidate the squares themselves must confirm.
  if (cx.contrast > 1.1 && cy.contrast > 1.1) {
    return _Coarse(cx, cy, skew, weak: true);
  }
  return null;
}

/// Brightness of a square's background: four patches near its corners,
/// where a piece rarely reaches, averaged without the brightest and darkest
/// (a coordinate letter or a stray piece corner). Null when a patch leaves
/// the image.
double? _cellTone(GrayImage img, double x0, double y0, double w, double h) {
  final pw = math.max(1.0, w * 0.2), ph = math.max(1.0, h * 0.2);
  final ix = w * 0.06, iy = h * 0.06;
  final v = <double>[];
  for (final (px, py) in [
    (x0 + ix, y0 + iy),
    (x0 + w - ix - pw, y0 + iy),
    (x0 + ix, y0 + h - iy - ph),
    (x0 + w - ix - pw, y0 + h - iy - ph),
  ]) {
    final xa = px.floor(), ya = py.floor();
    final xb = (px + pw).ceil(), yb = (py + ph).ceil();
    if (xa < 0 || ya < 0 || xb > img.width || yb > img.height) return null;
    v.add(img._boxSum(xa, ya, xb, yb) / ((xb - xa) * (yb - ya)));
  }
  v.sort();
  return (v[1] + v[2]) / 2;
}

/// How well every row and every column of the 8x8 cells from (x0, y0)
/// alternates between the board's two square tones, in grey levels: per
/// line the median of its seven neighbour differences (signed by the
/// board's colouring, so pieces in a few squares do not count), and the
/// weakest line decides — a lattice one square off has a whole line of
/// frame, margin or neighbouring diagram that does not alternate. Null when
/// a cell leaves the image.
double? _checkerScore(
    GrayImage img, double x0, double y0, double cw, double ch, double skew) {
  final t = Float64List(64);
  double parity = 0;
  for (int i = 0; i < 64; i++) {
    // The cell's centre, sheared back into the image.
    final (cx, cy) =
        _unshear(img, x0 + (i % 8 + 0.5) * cw, y0 + (i ~/ 8 + 0.5) * ch, skew);
    final v = _cellTone(img, cx - cw / 2, cy - ch / 2, cw, ch);
    if (v == null) return null;
    t[i] = v;
    parity += ((i % 8) + (i ~/ 8)).isEven ? v : -v;
  }
  final sign = parity >= 0 ? 1.0 : -1.0;
  double worst = double.infinity;
  final d = List<double>.filled(7, 0);
  for (int line = 0; line < 16; line++) {
    for (int k = 0; k < 7; k++) {
      final (a, b) = line < 8
          ? (line * 8 + k, line * 8 + k + 1)
          : (k * 8 + line - 8, (k + 1) * 8 + line - 8);
      final even = ((a % 8) + (a ~/ 8)).isEven;
      d[k] = (t[a] - t[b]) * (even ? sign : -sign);
    }
    d.sort();
    worst = math.min(worst, d[3]);
  }
  return worst;
}

/// The one-square shift of the lattice (each axis −1, 0 or +1) whose cells
/// form the cleanest checkerboard, if clearly cleaner than no shift.
(int, int) _checkerShift(GrayImage img, _Lattice x, _Lattice y, double skew) {
  // A lattice hanging off the image cannot be scored itself, but a fully
  // visible one a square over can replace it.
  final base = _checkerScore(img, x.start, y.start, x.step, y.step, skew);
  var best = (0, 0);
  // Clearly better, and a real alternation of a few grey levels at least.
  double bestScore =
      base == null ? _minAlternation : math.max(base * 1.25, _minAlternation);
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      final s = _checkerScore(img, x.start + dx * x.step, y.start + dy * y.step,
          x.step, y.step, skew);
      if (s != null && s > bestScore) {
        bestScore = s;
        best = (dx, dy);
      }
    }
  }
  return best;
}

/// Grey levels of alternation below which a lattice is not moved.
const double _minAlternation = 4;

/// Grey levels of alternation a faint lattice needs to be taken as a board.
const double _weakAlternation = 12;

/// Whole-range lattice search the first time; afterwards only near the last
/// answer (the restricted profile sharpens it, it does not move it far).
_Lattice? _searchNear(Float64List p, _Lattice? prev, int extent) {
  if (prev == null) {
    return _fitLattice(p,
        minStep: extent / 48, maxStep: extent / 8, stepInc: 0.25);
  }
  return _fitLattice(p,
      minStep: prev.step * 0.9,
      maxStep: prev.step * 1.1,
      stepInc: 0.125,
      startMin: prev.start - prev.step,
      startMax: prev.start + prev.step);
}

/// Largest column-to-row step ratio accepted (see the check in
/// [locateBoardGray]).
const double _maxAspect = 1.7;

/// Grey levels one sample of the coarse edge profile may add; see [_profile].
const double _edgeCap = 24;

class _Lattice {
  final double start;
  final double step;

  /// Mean inner-line strength relative to the mean strength halfway between
  /// lines — where a real board has square interiors (at most a piece's
  /// symmetric middle), and a chance lattice has as much edge as on its lines.
  final double contrast;

  _Lattice(this.start, this.step, this.contrast);

  bool get convincing => contrast > 1.4;

  (int, int) span(int limit) => (
        start.floor().clamp(0, limit - 1),
        (start + 8 * step).ceil().clamp(1, limit),
      );
}

/// Edge strength at each pixel boundary across the image.
///
/// With `vertical`, entry x (0..width) measures the boundary just left of
/// column x: Σ over rows [from, to) of |mean(I[x .. x+r)) − mean(I[x−r .. x))|.
/// Otherwise the same per row boundary, summed over columns [from, to).
///
/// [cap] limits what one sample adds. A board line is a modest edge on every
/// row it crosses, piece outlines are strong edges on a few: capped, the
/// line's consistency wins even on the palest themes, where the squares
/// differ by a few dozen grey levels and the pieces by two hundred.
Float64List _profile(GrayImage img,
    {required bool vertical,
    required int from,
    required int to,
    required int r,
    double cap = double.infinity,
    double skew = 0}) {
  final w = img.width, h = img.height, px = img.pixels;
  final len = vertical ? w : h;
  final p = Float64List(len + 1);
  if (len < 2 * r + 1) return p;
  final line = Float64List(len + 1); // prefix sums along one line
  // Sheared: line o's samples land |shift| further along, so lines turned
  // by atan(skew) add up at one position (see _unshear).
  final centre = (vertical ? h : w) / 2;
  for (int o = from; o < to; o++) {
    for (int i = 0; i < len; i++) {
      line[i + 1] = line[i] + (vertical ? px[o * w + i] : px[i * w + o]);
    }
    final shift =
        skew == 0 ? 0 : ((o - centre) * skew * (vertical ? -1 : 1)).round();
    for (int x = r; x <= len - r; x++) {
      final at = x + shift;
      if (at < 0 || at > len) continue;
      final after = line[x + r] - line[x];
      final before = line[x] - line[x - r];
      final d = (after - before).abs() / r;
      p[at] += d < cap ? d : cap;
    }
  }
  return p;
}

/// Best `(start, step)` such that start + k·step, k = 1..7, all sit on strong
/// edges. Scored by the five weakest of the seven (a lone spurious peak can't
/// carry a lattice; every inner line must be there).
///
/// Positions are read with linear interpolation, so the fit is sub-sample.
/// The coarse search ([exact] false) first smooths the profile with a
/// [1 2 1] kernel so a line blurred over two samples still has one peak.
_Lattice? _fitLattice(Float64List p,
    {required double minStep,
    required double maxStep,
    required double stepInc,
    double? startMin,
    double? startMax,
    bool exact = false}) {
  final n = p.length;
  if (n < 16) return null;
  final pm = Float64List(n);
  for (int i = 0; i < n; i++) {
    pm[i] = exact || i == 0 || i == n - 1
        ? p[i]
        : (p[i - 1] + 2 * p[i] + p[i + 1]) / 4;
  }
  double at(double pos) {
    if (pos < 0 || pos > n - 1) return 0;
    final i = pos.floor();
    final t = pos - i;
    return i + 1 < n ? pm[i] * (1 - t) + pm[i + 1] * t : pm[i];
  }

  double bestScore = double.negativeInfinity;
  double bestStart = 0, bestStep = 0;
  final vals = List<double>.filled(7, 0);
  minStep = math.max(minStep, 3);
  final startInc = exact ? 0.1 : 0.25;
  for (double step = minStep; step <= maxStep; step += stepInc) {
    final lo = startMin ?? -step * 0.5;
    final hi = startMax ?? n - 1 - 8 * step + step * 0.5;
    for (double start = lo; start <= hi; start += startInc) {
      bool ok = true;
      for (int k = 1; k <= 7; k++) {
        final pos = start + k * step;
        if (pos < 0 || pos > n - 1) {
          ok = false;
          break;
        }
        vals[k - 1] = at(pos);
      }
      if (!ok) continue;
      vals.sort();
      // With a strong frame, a lattice shifted by one square also finds
      // seven strong lines (the frame standing in for an inner line). Only
      // the true one has an edge at both k = 0 and k = 8, so the weaker of
      // those two breaks the tie.
      final outer = math.min(at(start), at(start + 8 * step));
      final score =
          vals[0] + vals[1] + vals[2] + vals[3] + vals[4] + 0.5 * outer;
      if (score > bestScore) {
        bestScore = score;
        bestStart = start;
        bestStep = step;
      }
    }
  }
  if (bestScore == double.negativeInfinity) return null;
  double inner = 0, mid = 0;
  for (int k = 1; k <= 7; k++) {
    inner += at(bestStart + k * bestStep);
  }
  for (int k = 0; k < 8; k++) {
    mid += at(bestStart + (k + 0.5) * bestStep);
  }
  return _Lattice(bestStart, bestStep, (inner / 7) / math.max(mid / 8, 1.0));
}

_Lattice _refine(GrayImage full, _Lattice coarse, double f,
    {required bool vertical,
    required (double, double) spanOther,
    double skew = 0}) {
  final limit = vertical ? full.height : full.width;
  final a = spanOther.$1.floor().clamp(0, limit - 1);
  final b = spanOther.$2.ceil().clamp(a + 1, limit);
  final step = coarse.step * f, start = coarse.start * f;
  // Side windows of ~1/12 square: wide enough to average print hatching out,
  // narrow enough that neighbouring lines never share a window.
  final r = math.max(1, (step / 12).round());
  final p =
      _profile(full, vertical: vertical, from: a, to: b, r: r, skew: skew);
  final refined = _fitLattice(p,
      minStep: step - f,
      maxStep: step + f,
      stepInc: 0.05,
      startMin: start - 1.5 * f,
      startMax: start + 1.5 * f,
      exact: true);
  return refined ?? _Lattice(start, step, coarse.contrast);
}
