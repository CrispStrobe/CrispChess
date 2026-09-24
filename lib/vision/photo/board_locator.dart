/// Finds the four corners of a physical chessboard in a photo.
///
/// A port of chesscog's localiser (Wölflein & Arandjelović 2021,
/// `chesscog/corner_detection/detect_corners.py`, MIT licence), step for
/// step and with its configuration (`config/corner_detection.yaml`):
///
///  1. resize to 1200 px wide, greyscale, Canny(90, 400);
///  2. Hough lines (1 px, 0.5 deg, 150 votes), keep those within 30 deg of
///     horizontal or vertical, give up above 400 lines;
///  3. split them into two families by average-linkage clustering of their
///     angles, and merge near-duplicates in each family (DBSCAN, eps 12 px,
///     on where they cross the other family's mean line);
///  4. RANSAC: two random rows and two random columns fix a homography to
///     the unit square; every intersection is warped, and the integer grid
///     scale (1..8 per axis) that puts most of them near integers wins;
///     outlier rows/columns are dropped and the survivors quantised to grid
///     coordinates — the configuration with the most inliers is kept;
///  5. refit the homography on all inliers, warp the image to 50 px squares
///     with five squares of margin, and grow the grid to 9 x 9 lines by
///     Sobel + Canny edge evidence just outside it;
///  6. map the four outer corners back to the image.
///
/// Quirks of the original are kept on purpose (they are what its accuracy
/// was measured with) and marked "chesscog quirk".
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'hough.dart';
import 'image_ops.dart';

/// chesscog's `config/corner_detection.yaml`.
class LocatorConfig {
  final int resizeWidth;
  final double cannyLow, cannyHigh;
  final int houghThreshold;
  final double diagonalThresholdDeg;
  final int maxLines;
  final double dbscanEps;
  final double ransacOffsetTolerance;
  final double ransacBestSolutionTolerance;
  final double maxOutlierRatioPerLine;
  final int minRansacIterations;
  final int minInliers;
  final int maxRansacIterations;
  final int lineWidth;
  final int warpedSquare;
  final int surroundingSquares;
  final double verticalCannyLow, verticalCannyHigh;
  final double horizontalCannyLow, horizontalCannyHigh;

  const LocatorConfig({
    this.resizeWidth = 1200,
    this.cannyLow = 90,
    this.cannyHigh = 400,
    this.houghThreshold = 150,
    this.diagonalThresholdDeg = 30,
    this.maxLines = 400,
    this.dbscanEps = 12,
    this.ransacOffsetTolerance = 0.1,
    this.ransacBestSolutionTolerance = 0.15,
    this.maxOutlierRatioPerLine = 0.7,
    this.minRansacIterations = 200,
    this.minInliers = 30,
    this.maxRansacIterations = 10000,
    this.lineWidth = 4,
    this.warpedSquare = 50,
    this.surroundingSquares = 5,
    this.verticalCannyLow = 100,
    this.verticalCannyHigh = 200,
    this.horizontalCannyLow = 120,
    this.horizontalCannyHigh = 300,
  });
}

/// The board could not be found in the photo.
class BoardNotLocatedException implements Exception {
  final String reason;
  const BoardNotLocatedException(this.reason);
  @override
  String toString() => 'BoardNotLocatedException: $reason';
}

/// Timings and intermediate counts, for tests and tuning.
class LocatorStats {
  int edgePixels = 0;
  int houghLines = 0;
  int horizontalLines = 0;
  int verticalLines = 0;
  int ransacIterations = 0;
  int inliers = 0;
  final Map<String, int> ms = {};

  @override
  String toString() => 'edges=$edgePixels lines=$houghLines '
      'h=$horizontalLines v=$verticalLines iters=$ransacIterations '
      'inliers=$inliers ms=$ms';
}

/// Board corners in the coordinates of the image passed to [locateBoard]:
/// top left, top right, bottom right, bottom left (as they appear in the
/// image, not in chess terms).
class BoardCorners {
  final List<Pt> corners;
  final LocatorStats stats;
  const BoardCorners(this.corners, this.stats);
}

/// Resizes [img] to the locator's working width (chesscog's
/// `resize_image`). Returns the image and the factor applied.
(RgbImage, double) resizeForLocator(RgbImage img,
    {int width = 1200, bool antialias = true}) {
  if (img.width == width) return (img, 1.0);
  final scale = width / img.width;
  final h = (img.height * scale).floor();
  return (
    RgbImage(
        width,
        h,
        resizeBilinear(img.data, img.width, img.height, width, h, 3,
            antialias: antialias)),
    scale
  );
}

/// Locates the board in [img]. The image is first brought to
/// [LocatorConfig.resizeWidth]; corners are returned in [img]'s pixels.
/// Throws [BoardNotLocatedException].
BoardCorners locateBoard(RgbImage img,
    {LocatorConfig cfg = const LocatorConfig(), int seed = 0}) {
  final (small, scale) = resizeForLocator(img, width: cfg.resizeWidth);
  final r = locateBoardGray(small.toGray(), cfg: cfg, seed: seed);
  if (scale == 1.0) return r;
  return BoardCorners(
      [for (final p in r.corners) Pt(p.x / scale, p.y / scale)], r.stats);
}

/// The locator on an already resized greyscale image (chesscog's
/// `find_corners` after its resize).
BoardCorners locateBoardGray(GrayU8 gray,
    {LocatorConfig cfg = const LocatorConfig(), int seed = 0}) {
  final stats = LocatorStats();
  final sw = Stopwatch()..start();
  void lap(String k) {
    stats.ms[k] = sw.elapsedMilliseconds;
    sw.reset();
  }

  final w = gray.width, h = gray.height;
  final edges = canny(gray.px, w, h, cfg.cannyLow, cfg.cannyHigh);
  for (final e in edges) {
    if (e != 0) stats.edgePixels++;
  }
  lap('canny');
  var lines = houghLines(edges, w, h, 1, math.pi / 360, cfg.houghThreshold);
  lap('hough');
  lines = _fixNegativeRho(lines);
  final thr = cfg.diagonalThresholdDeg * math.pi / 180;
  lines = [
    for (final l in lines)
      if (l.theta.abs() < thr || (l.theta - math.pi / 2).abs() < thr) l
  ];
  stats.houghLines = lines.length;
  if (lines.length > cfg.maxLines) {
    throw const BoardNotLocatedException('too many lines in the image');
  }
  if (lines.length < 4) {
    throw const BoardNotLocatedException('too few lines');
  }
  final (allH, allV) = _clusterHorizontalAndVertical(lines);
  if (allH.isEmpty || allV.isEmpty) {
    throw const BoardNotLocatedException('only one line family');
  }
  final hLines = _eliminateSimilarLines(allH, allV, cfg.dbscanEps);
  final vLines = _eliminateSimilarLines(allV, allH, cfg.dbscanEps);
  stats.horizontalLines = hLines.length;
  stats.verticalLines = vLines.length;
  if (hLines.length < 2 || vLines.length < 2) {
    throw const BoardNotLocatedException('fewer than two lines per family');
  }
  lap('lines');

  final nr = hLines.length, nc = vLines.length;
  final ix = Float64List(nr * nc), iy = Float64List(nr * nc);
  for (int r = 0; r < nr; r++) {
    for (int c = 0; c < nc; c++) {
      final p = _intersection(hLines[r], vLines[c]);
      ix[r * nc + c] = p.x;
      iy[r * nc + c] = p.y;
    }
  }

  final rnd = math.Random(seed);
  int bestInliers = 0;
  _Config? best;
  int it = 0;
  final wx = Float64List(nr * nc), wy = Float64List(nr * nc);
  while (it < cfg.minRansacIterations || bestInliers < cfg.minInliers) {
    final (r1, r2) = _choose2(rnd, nr);
    final (c1, c2) = _choose2(rnd, nc);
    final m = findHomography([
      Pt(ix[r1 * nc + c1], iy[r1 * nc + c1]),
      Pt(ix[r1 * nc + c2], iy[r1 * nc + c2]),
      Pt(ix[r2 * nc + c2], iy[r2 * nc + c2]),
      Pt(ix[r2 * nc + c1], iy[r2 * nc + c1]),
    ], const [
      Pt(0, 0),
      Pt(1, 0),
      Pt(1, 1),
      Pt(0, 1)
    ]);
    it++;
    if (m != null) {
      for (int i = 0; i < nr * nc; i++) {
        final p = warpPoint(m, ix[i], iy[i]);
        wx[i] = p.x;
        wy[i] = p.y;
      }
      final d = _discardOutliers(cfg, wx, wy, nr, nc);
      final n = d.rows.length * d.cols.length;
      if (n > bestInliers) {
        final q = _quantize(cfg, d, wx, wy, ix, iy, nc);
        if (q != null && q.numInliers > bestInliers) {
          bestInliers = q.numInliers;
          best = q;
        }
      }
    }
    if (it > cfg.maxRansacIterations) {
      throw const BoardNotLocatedException('RANSAC produced no viable results');
    }
  }
  stats.ransacIterations = it;
  stats.inliers = bestInliers;
  lap('ransac');
  final b = best!;

  final m = findHomography(b.imagePoints, b.gridPoints);
  if (m == null) throw const BoardNotLocatedException('degenerate refit');
  final minv = mat3Inv(m);
  final dw = b.warpedW, dh = b.warpedH;
  final warped = warpPerspective(gray.px, w, h, 1, minv, dw, dh);
  final borders = Uint8List(w * h);
  for (int y = 3; y < h - 3; y++) {
    borders.fillRange(y * w + 3, y * w + w - 3, 1);
  }
  final wb = warpPerspective(borders, w, h, 1, minv, dw, dh);
  final mask = Uint8List(dw * dh);
  for (int i = 0; i < mask.length; i++) {
    mask[i] = wb[i] == 1 ? 1 : 0;
  }
  lap('warp');

  final sq = cfg.warpedSquare;
  var (xmin, xmax) =
      _verticalBorders(cfg, warped, mask, dw, dh, b.xmin, b.xmax);
  // warped_mask[:, :scaled_xmin] = warped_mask[:, scaled_xmax:] = False
  final sxmin = _pyIndex(xmin * sq, dw), sxmax = _pyIndex(xmax * sq, dw);
  for (int y = 0; y < dh; y++) {
    for (int x = 0; x < dw; x++) {
      if (x < sxmin || x >= sxmax) mask[y * dw + x] = 0;
    }
  }
  var (ymin, ymax) =
      _horizontalBorders(cfg, warped, mask, dw, dh, b.ymin, b.ymax);
  lap('borders');

  final corners = [
    for (final (gx, gy) in [
      (xmin, ymin),
      (xmax, ymin),
      (xmax, ymax),
      (xmin, ymax)
    ])
      warpPoint(minv, (gx * sq).toDouble(), (gy * sq).toDouble())
  ];
  return BoardCorners(sortCornerPoints(corners), stats);
}

List<PolarLine> _fixNegativeRho(List<PolarLine> lines) => [
      for (final l in lines)
        l.rho < 0 ? PolarLine(-l.rho, l.theta - math.pi) : l
    ];

double _angleDiff(double x, double y) {
  // np.mod(|x - y|, 2 pi), then min(diff, pi - diff).
  final diff = (x - y).abs() % (2 * math.pi);
  return math.min(diff, math.pi - diff);
}

/// Average-linkage agglomerative clustering into two groups by angle, then
/// the group closer to vertical theta (lines at theta ~ 0) is "vertical".
(List<PolarLine>, List<PolarLine>) _clusterHorizontalAndVertical(
    List<PolarLine> input) {
  // _sort_lines: by rho (stable).
  final lines = [...input];
  _stableSortBy(lines, (l) => l.rho);
  final n = lines.length;
  final label = List<int>.generate(n, (i) => i);
  if (n == 2) {
    label[1] = 1;
  } else {
    // Cluster distances (average linkage), updated with Lance-Williams.
    final d = Float64List(n * n);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        d[i * n + j] = _angleDiff(lines[i].theta, lines[j].theta);
      }
    }
    final size = List<int>.filled(n, 1);
    final active = List<bool>.filled(n, true);
    // Each point's cluster representative.
    final rep = List<int>.generate(n, (i) => i);
    int clusters = n;
    // Nearest-neighbour cache per active cluster.
    final nn = Int32List(n);
    final nnd = Float64List(n);
    void refresh(int i) {
      double bd = double.infinity;
      int bj = -1;
      for (int j = 0; j < n; j++) {
        if (j == i || !active[j]) continue;
        final v = d[i * n + j];
        if (v < bd) {
          bd = v;
          bj = j;
        }
      }
      nn[i] = bj;
      nnd[i] = bd;
    }

    for (int i = 0; i < n; i++) {
      refresh(i);
    }
    while (clusters > 2) {
      int a = -1;
      double bd = double.infinity;
      for (int i = 0; i < n; i++) {
        if (active[i] && nnd[i] < bd) {
          bd = nnd[i];
          a = i;
        }
      }
      int bIdx = nn[a];
      final lo = math.min(a, bIdx), hi = math.max(a, bIdx);
      // merge hi into lo
      for (int k = 0; k < n; k++) {
        if (!active[k] || k == lo || k == hi) continue;
        final v = (d[lo * n + k] * size[lo] + d[hi * n + k] * size[hi]) /
            (size[lo] + size[hi]);
        d[lo * n + k] = v;
        d[k * n + lo] = v;
      }
      size[lo] += size[hi];
      active[hi] = false;
      for (int k = 0; k < n; k++) {
        if (rep[k] == hi) rep[k] = lo;
      }
      clusters--;
      for (int i = 0; i < n; i++) {
        if (!active[i]) continue;
        if (i == lo || nn[i] == lo || nn[i] == hi) {
          refresh(i);
        } else if (d[i * n + lo] < nnd[i]) {
          nn[i] = lo;
          nnd[i] = d[i * n + lo];
        }
      }
    }
    final roots = [
      for (int i = 0; i < n; i++)
        if (active[i]) i
    ];
    for (int k = 0; k < n; k++) {
      label[k] = rep[k] == roots[0] ? 0 : 1;
    }
  }
  double mean(int c) {
    double s = 0;
    int k = 0;
    for (int i = 0; i < n; i++) {
      if (label[i] == c) {
        s += _angleDiff(lines[i].theta, 0);
        k++;
      }
    }
    return k == 0 ? double.nan : s / k;
  }

  final hc = mean(0) > mean(1) ? 0 : 1;
  return (
    [
      for (int i = 0; i < n; i++)
        if (label[i] == hc) lines[i]
    ],
    [
      for (int i = 0; i < n; i++)
        if (label[i] != hc) lines[i]
    ],
  );
}

Pt _intersection(PolarLine a, PolarLine b) =>
    _intersect(a.rho, a.theta, b.rho, b.theta);

Pt _intersect(double rho1, double t1, double rho2, double t2) {
  final c1 = math.cos(t1), c2 = math.cos(t2);
  final s1 = math.sin(t1), s2 = math.sin(t2);
  final x = (s1 * rho2 - s2 * rho1) / (c2 * s1 - c1 * s2);
  final y = (c1 * rho2 - c2 * rho1) / (s2 * c1 - s1 * c2);
  return Pt(x, y);
}

/// Merge lines crossing the other family's mean line within [eps] of each
/// other (DBSCAN with min_samples 1 = connected components), keeping each
/// group's median-rho line; groups in order of their first member.
List<PolarLine> _eliminateSimilarLines(
    List<PolarLine> lines, List<PolarLine> perpendicular, double eps) {
  double pr = 0, pt = 0;
  for (final l in perpendicular) {
    pr += l.rho;
    pt += l.theta;
  }
  pr /= perpendicular.length;
  pt /= perpendicular.length;
  final pts = [for (final l in lines) _intersect(l.rho, l.theta, pr, pt)];
  final n = lines.length;
  final label = List<int>.filled(n, -1);
  int next = 0;
  for (int i = 0; i < n; i++) {
    if (label[i] != -1) continue;
    label[i] = next;
    final queue = [i];
    while (queue.isNotEmpty) {
      final a = queue.removeLast();
      for (int j = 0; j < n; j++) {
        if (label[j] != -1) continue;
        final dx = pts[a].x - pts[j].x, dy = pts[a].y - pts[j].y;
        // NaN distances (parallel lines) never join.
        if (dx * dx + dy * dy <= eps * eps) {
          label[j] = next;
          queue.add(j);
        }
      }
    }
    next++;
  }
  final out = <PolarLine>[];
  for (int c = 0; c < next; c++) {
    final members = [
      for (int i = 0; i < n; i++)
        if (label[i] == c) lines[i]
    ];
    final order = List<int>.generate(members.length, (i) => i);
    _stableSortBy(order, (i) => members[i].rho);
    out.add(members[order[members.length ~/ 2]]);
  }
  return out;
}

void _stableSortBy<T>(List<T> list, double Function(T) key) {
  final idx = List<int>.generate(list.length, (i) => i);
  final keys = [for (final e in list) key(e)];
  idx.sort((a, b) {
    final c = keys[a].compareTo(keys[b]);
    return c != 0 ? c : a - b;
  });
  final copy = [...list];
  for (int i = 0; i < idx.length; i++) {
    list[i] = copy[idx[i]];
  }
}

(int, int) _choose2(math.Random rnd, int n) {
  final a = rnd.nextInt(n);
  int b = rnd.nextInt(n - 1);
  if (b >= a) b++;
  return a < b ? (a, b) : (b, a);
}

double _rint(double v) {
  final f = v.floorToDouble();
  final d = v - f;
  if (d > 0.5) return f + 1;
  if (d < 0.5) return f;
  return (f % 2 == 0) ? f : f + 1;
}

/// chesscog's `_find_best_scale` over one coordinate of the kept points.
/// Returns the scale and a per-point inlier mask.
(int, Uint8List) _findBestScale(LocatorConfig cfg, Float64List values) {
  final n = values.length;
  final counts = List<int>.filled(8, 0);
  final masks = List.generate(8, (_) => Uint8List(n));
  for (int s = 1; s <= 8; s++) {
    final tol = cfg.ransacOffsetTolerance / s;
    final m = masks[s - 1];
    for (int i = 0; i < n; i++) {
      final v = values[i] * s;
      if ((_rint(v) - v).abs() < tol) {
        m[i] = 1;
        counts[s - 1]++;
      }
    }
  }
  final best = counts.reduce(math.max);
  int index = 0;
  for (int s = 0; s < 8; s++) {
    if (counts[s] > (1 - cfg.ransacBestSolutionTolerance) * best) {
      index = s;
      break;
    }
  }
  return (index + 1, masks[index]);
}

class _Kept {
  final List<int> rows, cols;
  final int hScale, vScale;
  _Kept(this.rows, this.cols, this.hScale, this.vScale);
}

_Kept _discardOutliers(
    LocatorConfig cfg, Float64List wx, Float64List wy, int nr, int nc) {
  final (hs, hm) = _findBestScale(cfg, wx);
  final (vs, vm) = _findBestScale(cfg, wy);
  final rowCount = List<int>.filled(nr, 0), colCount = List<int>.filled(nc, 0);
  for (int r = 0; r < nr; r++) {
    for (int c = 0; c < nc; c++) {
      if (hm[r * nc + c] == 1 && vm[r * nc + c] == 1) {
        rowCount[r]++;
        colCount[c]++;
      }
    }
  }
  final rowsAny = rowCount.where((v) => v > 0).length;
  final colsAny = colCount.where((v) => v > 0).length;
  // chesscog quirk: a row's inlier count is divided by the number of rows
  // with any inlier (not by the number of columns), and vice versa.
  final rows = [
    for (int r = 0; r < nr; r++)
      if (rowsAny > 0 && rowCount[r] / rowsAny > cfg.maxOutlierRatioPerLine) r
  ];
  final cols = [
    for (int c = 0; c < nc; c++)
      if (colsAny > 0 && colCount[c] / colsAny > cfg.maxOutlierRatioPerLine) c
  ];
  return _Kept(rows, cols, hs, vs);
}

class _Config {
  final int xmin, xmax, ymin, ymax;
  final List<Pt> imagePoints;
  final List<Pt> gridPoints;
  final int warpedW, warpedH;
  int get numInliers => imagePoints.length;
  _Config(this.xmin, this.xmax, this.ymin, this.ymax, this.imagePoints,
      this.gridPoints, this.warpedW, this.warpedH);
}

_Config? _quantize(LocatorConfig cfg, _Kept k, Float64List wx, Float64List wy,
    Float64List ix, Float64List iy, int nc) {
  final nkr = k.rows.length, nkc = k.cols.length;
  if (nkr == 0 || nkc == 0) return null;
  // Column means of scaled x, row means of scaled y.
  final colX = List<int>.filled(nkc, 0), rowY = List<int>.filled(nkr, 0);
  for (int j = 0; j < nkc; j++) {
    double s = 0;
    for (final r in k.rows) {
      s += wx[r * nc + k.cols[j]] * k.hScale;
    }
    if (!(s / nkr).isFinite || (s / nkr).abs() > 1e9) return null;
    colX[j] = _rint(s / nkr).toInt();
  }
  for (int i = 0; i < nkr; i++) {
    double s = 0;
    for (final c in k.cols) {
      s += wy[k.rows[i] * nc + c] * k.vScale;
    }
    if (!(s / nkc).isFinite || (s / nkc).abs() > 1e9) return null;
    rowY[i] = _rint(s / nkc).toInt();
  }
  // np.unique(..., return_index=True): sorted values, first occurrence.
  List<(int, int)> unique(List<int> v) {
    final seen = <int, int>{};
    for (int i = 0; i < v.length; i++) {
      seen.putIfAbsent(v[i], () => i);
    }
    final keys = seen.keys.toList()..sort();
    return [for (final key in keys) (key, seen[key]!)];
  }

  var cu = unique(colX), ru = unique(rowY);
  int xmin = cu.first.$1, xmax = cu.last.$1;
  int ymin = ru.first.$1, ymax = ru.last.$1;
  while (xmax - xmin > 8) {
    xmax--;
    xmin++;
  }
  while (ymax - ymin > 8) {
    ymax--;
    ymin++;
  }
  cu = [
    for (final e in cu)
      if (e.$1 >= xmin && e.$1 <= xmax) e
  ];
  // chesscog quirk: rows are filtered with the column bounds.
  ru = [
    for (final e in ru)
      if (e.$1 >= xmin && e.$1 <= xmax) e
  ];
  if (cu.isEmpty || ru.isEmpty) return null;
  final t = cfg.surroundingSquares, sq = cfg.warpedSquare;
  final tx = -xmin + t, ty = -ymin + t;
  final img = <Pt>[], grid = <Pt>[];
  for (final (ry, ri) in ru) {
    for (final (cx, ci) in cu) {
      final src = k.rows[ri] * nc + k.cols[ci];
      img.add(Pt(ix[src], iy[src]));
      grid.add(Pt(((cx + tx) * sq).toDouble(), ((ry + ty) * sq).toDouble()));
    }
  }
  return _Config(xmin + tx, xmax + tx, ymin + ty, ymax + ty, img, grid,
      (xmax + tx + t) * sq, (ymax + ty + t) * sq);
}

/// Python slice bound semantics for a start/stop index on a length-[n] axis.
int _pyIndex(int i, int n) {
  if (i < 0) i += n;
  return i.clamp(0, n);
}

/// Sobel magnitude along one axis, masked, normalised to 0..255 (truncated)
/// as chesscog's `_detect_edges` does for a float image, then Canny, masked.
Uint8List _borderEdges(Uint8List warped, Uint8List mask, int w, int h,
    {required bool dx, required double low, required double high}) {
  final g = sobel3(warped, w, h, dx: dx);
  int mx = 0;
  for (int i = 0; i < g.length; i++) {
    final v = mask[i] == 1 ? g[i].abs() : 0;
    g[i] = v;
    if (v > mx) mx = v;
  }
  final u8 = Uint8List(w * h);
  if (mx > 0) {
    for (int i = 0; i < g.length; i++) {
      u8[i] = (g[i] / mx * 255).toInt();
    }
  }
  final e = canny(u8, w, h, low, high);
  for (int i = 0; i < e.length; i++) {
    if (mask[i] == 0) e[i] = 0;
  }
  return e;
}

(int, int) _verticalBorders(LocatorConfig cfg, Uint8List warped, Uint8List mask,
    int w, int h, int xmin, int xmax) {
  final e = _borderEdges(warped, mask, w, h,
      dx: true, low: cfg.verticalCannyLow, high: cfg.verticalCannyHigh);
  final t = cfg.lineWidth ~/ 2;
  int score(int line) {
    final x = line * cfg.warpedSquare;
    final a = _pyIndex(x - t, w), b = _pyIndex(x + t + 1, w);
    if (b <= a) {
      throw const BoardNotLocatedException('border search left the image');
    }
    int s = 0;
    for (int y = 0; y < h; y++) {
      int m = 0;
      for (int xx = a; xx < b; xx++) {
        final v = e[y * w + xx];
        if (v > m) m = v;
      }
      s += m;
    }
    return s;
  }

  while (xmax - xmin < 8) {
    final top = score(xmax + 1), bottom = score(xmin - 1);
    if (top > bottom) {
      xmax++;
    } else {
      xmin--;
    }
  }
  return (xmin, xmax);
}

(int, int) _horizontalBorders(LocatorConfig cfg, Uint8List warped,
    Uint8List mask, int w, int h, int ymin, int ymax) {
  final e = _borderEdges(warped, mask, w, h,
      dx: false, low: cfg.horizontalCannyLow, high: cfg.horizontalCannyHigh);
  final t = cfg.lineWidth ~/ 2;
  int score(int line) {
    final y = line * cfg.warpedSquare;
    final a = _pyIndex(y - t, h), b = _pyIndex(y + t + 1, h);
    if (b <= a) {
      throw const BoardNotLocatedException('border search left the image');
    }
    int s = 0;
    for (int x = 0; x < w; x++) {
      int m = 0;
      for (int yy = a; yy < b; yy++) {
        final v = e[yy * w + x];
        if (v > m) m = v;
      }
      s += m;
    }
    return s;
  }

  while (ymax - ymin < 8) {
    final top = score(ymax + 1), bottom = score(ymin - 1);
    if (top > bottom) {
      ymax++;
    } else {
      ymin--;
    }
  }
  return (ymin, ymax);
}
