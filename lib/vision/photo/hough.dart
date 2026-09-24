/// OpenCV's standard Hough line transform (`cv2.HoughLines`), reproduced
/// down to its float32 trig tables, rounding, local-maximum test and vote
/// ordering, so the photo locator sees the same lines chesscog does.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A line in Hesse normal form: x cos(theta) + y sin(theta) = rho.
class PolarLine {
  final double rho;
  final double theta;
  const PolarLine(this.rho, this.theta);

  @override
  String toString() =>
      'PolarLine(${rho.toStringAsFixed(1)}, ${(theta * 180 / math.pi).toStringAsFixed(2)} deg)';
}

final _f32 = Float32List(1);
double _toF32(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// `cv2.HoughLines(edges, rho, theta, threshold)` with min_theta 0 and
/// max_theta pi. [edges] is non-zero on edge pixels. Lines come strongest
/// first, ties by accumulator index, as OpenCV sorts them.
List<PolarLine> houghLines(Uint8List edges, int width, int height, double rho,
    double theta, int threshold,
    {int maxLines = 1 << 30}) {
  final irho = 1 / rho;
  int numangle = ((math.pi - 0) / theta).floor() + 1;
  if (numangle > 1 && (math.pi - (numangle - 1) * theta).abs() < theta / 2) {
    numangle--;
  }
  final numrho = (((width + height) * 2 + 1) / rho).round();
  final tabSin = Float32List(numangle), tabCos = Float32List(numangle);
  final thetaF = _toF32(theta);
  double ang = 0; // accumulated in float, as OpenCV does
  for (int n = 0; n < numangle; n++) {
    tabSin[n] = math.sin(ang) * irho;
    tabCos[n] = math.cos(ang) * irho;
    ang = _toF32(ang + thetaF);
  }
  final stride = numrho + 2;
  final accum = Int32List((numangle + 2) * stride);
  final half = (numrho - 1) ~/ 2;
  // Collect edge pixels once; the inner loop is then angle-major, which keeps
  // one accumulator row hot.
  int count = 0;
  for (int i = 0; i < edges.length; i++) {
    if (edges[i] != 0) count++;
  }
  final xs = Float32List(count), ys = Float32List(count);
  for (int i = 0, k = 0; i < edges.length; i++) {
    if (edges[i] != 0) {
      xs[k] = (i % width).toDouble();
      ys[k] = (i ~/ width).toDouble();
      k++;
    }
  }
  final tmp = Float32List(2);
  for (int n = 0; n < numangle; n++) {
    final c = tabCos[n], s = tabSin[n];
    final base = (n + 1) * stride + 1 + half;
    for (int k = 0; k < count; k++) {
      // OpenCV sums float32 products and rounds half to even. In double the
      // sum differs from that only in the last float bits, which matters
      // only right at a .5 boundary — redo those few in float32.
      final v = xs[k] * c + ys[k] * s;
      final f = v.floorToDouble();
      final d = v - f;
      int r;
      if ((d - 0.5).abs() > 1e-3) {
        r = d > 0.5 ? f.toInt() + 1 : f.toInt();
      } else {
        tmp[0] = xs[k] * c;
        tmp[1] = ys[k] * s;
        tmp[0] = tmp[0] + tmp[1];
        r = _roundHalfEven(tmp[0]);
      }
      accum[base + r]++;
    }
  }
  final found = <int>[];
  for (int r = 0; r < numrho; r++) {
    for (int n = 0; n < numangle; n++) {
      final b = (n + 1) * stride + r + 1;
      final v = accum[b];
      if (v > threshold &&
          v > accum[b - 1] &&
          v >= accum[b + 1] &&
          v > accum[b - stride] &&
          v >= accum[b + stride]) {
        found.add(b);
      }
    }
  }
  found.sort((a, b) {
    final d = accum[b] - accum[a];
    return d != 0 ? d : a - b;
  });
  final scale = 1.0 / stride;
  final out = <PolarLine>[];
  for (int i = 0; i < found.length && i < maxLines; i++) {
    final idx = found[i];
    final n = (idx * scale).floor() - 1;
    final r = idx - (n + 1) * stride - 1;
    out.add(PolarLine(
        _toF32((r - (numrho - 1) * 0.5) * rho), _toF32(0 + n * thetaF)));
  }
  return out;
}

int _roundHalfEven(double v) {
  final f = v.floorToDouble();
  final d = v - f;
  if (d > 0.5) return f.toInt() + 1;
  if (d < 0.5) return f.toInt();
  final i = f.toInt();
  return i.isEven ? i : i + 1;
}
