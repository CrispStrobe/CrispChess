/// Homographies for the photo board locator: OpenCV's `findHomography`
/// (method 0: normalised DLT, then Levenberg-Marquardt on the reprojection
/// error when there are more than four points), inversion and point warping.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A 2-D point.
class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// 3x3 matrix product, row-major.
Float64List mat3Mul(Float64List a, Float64List b) {
  final o = Float64List(9);
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      o[i * 3 + j] =
          a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
    }
  }
  return o;
}

/// 3x3 inverse, row-major. Throws on a singular matrix.
Float64List mat3Inv(Float64List m) {
  final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  final det = a * A + b * B + c * C;
  if (det == 0 || det.isNaN) throw StateError('singular homography');
  final r = 1 / det;
  return Float64List.fromList([
    A * r, -(b * i - c * h) * r, (b * f - c * e) * r, //
    B * r, (a * i - c * g) * r, -(a * f - c * d) * r, //
    C * r, -(a * h - b * g) * r, (a * e - b * d) * r,
  ]);
}

/// Applies homography [m] to a point.
Pt warpPoint(Float64List m, double x, double y) {
  final w = m[6] * x + m[7] * y + m[8];
  return Pt((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w);
}

/// `cv2.findHomography(src, dst)` with method 0. Null when degenerate.
Float64List? findHomography(List<Pt> src, List<Pt> dst) {
  final n = src.length;
  if (n < 4 || dst.length != n) return null;
  // Four points fit exactly; solving the 8x8 system directly gives the same
  // homography as the DLT's null vector, several times faster (the RANSAC
  // calls this hundreds of times).
  final h = n == 4 ? _fourPoint(src, dst) : _dlt(src, dst);
  if (h == null) return null;
  if (n > 4) _refineLM(h, src, dst, 10);
  return h;
}

Float64List? _fourPoint(List<Pt> src, List<Pt> dst) {
  final a = Float64List(64), b = Float64List(8);
  for (int i = 0; i < 4; i++) {
    final X = src[i].x, Y = src[i].y, x = dst[i].x, y = dst[i].y;
    final r = 2 * i;
    a.setAll(r * 8, [X, Y, 1, 0, 0, 0, -x * X, -x * Y]);
    a.setAll((r + 1) * 8, [0, 0, 0, X, Y, 1, -y * X, -y * Y]);
    b[r] = x;
    b[r + 1] = y;
  }
  final s = _solve(a, b, 8);
  if (s == null || s.any((v) => !v.isFinite)) return null;
  return Float64List.fromList([...s, 1]);
}

/// OpenCV's HomographyEstimatorCallback::runKernel.
Float64List? _dlt(List<Pt> src, List<Pt> dst) {
  final n = src.length;
  double cMx = 0, cMy = 0, cmx = 0, cmy = 0;
  for (int i = 0; i < n; i++) {
    cMx += src[i].x;
    cMy += src[i].y;
    cmx += dst[i].x;
    cmy += dst[i].y;
  }
  cMx /= n;
  cMy /= n;
  cmx /= n;
  cmy /= n;
  double sMx = 0, sMy = 0, smx = 0, smy = 0;
  for (int i = 0; i < n; i++) {
    smx += (dst[i].x - cmx).abs();
    smy += (dst[i].y - cmy).abs();
    sMx += (src[i].x - cMx).abs();
    sMy += (src[i].y - cMy).abs();
  }
  const eps = 2.220446049250313e-16;
  if (smx.abs() < eps ||
      smy.abs() < eps ||
      sMx.abs() < eps ||
      sMy.abs() < eps) {
    return null;
  }
  smx = n / smx;
  smy = n / smy;
  sMx = n / sMx;
  sMy = n / sMy;
  final ltl = Float64List(81);
  final lx = Float64List(9), ly = Float64List(9);
  for (int i = 0; i < n; i++) {
    final x = (dst[i].x - cmx) * smx, y = (dst[i].y - cmy) * smy;
    final X = (src[i].x - cMx) * sMx, Y = (src[i].y - cMy) * sMy;
    lx
      ..[0] = X
      ..[1] = Y
      ..[2] = 1
      ..[3] = 0
      ..[4] = 0
      ..[5] = 0
      ..[6] = -x * X
      ..[7] = -x * Y
      ..[8] = -x;
    ly
      ..[0] = 0
      ..[1] = 0
      ..[2] = 0
      ..[3] = X
      ..[4] = Y
      ..[5] = 1
      ..[6] = -y * X
      ..[7] = -y * Y
      ..[8] = -y;
    for (int j = 0; j < 9; j++) {
      for (int k = j; k < 9; k++) {
        ltl[j * 9 + k] += lx[j] * lx[k] + ly[j] * ly[k];
      }
    }
  }
  for (int j = 0; j < 9; j++) {
    for (int k = 0; k < j; k++) {
      ltl[j * 9 + k] = ltl[k * 9 + j];
    }
  }
  final v = _smallestEigenvector(ltl, 9);
  final h0 = Float64List.fromList(v);
  final invHnorm =
      Float64List.fromList([1 / smx, 0, cmx, 0, 1 / smy, cmy, 0, 0, 1]);
  final hnorm2 =
      Float64List.fromList([sMx, 0, -cMx * sMx, 0, sMy, -cMy * sMy, 0, 0, 1]);
  final h = mat3Mul(mat3Mul(invHnorm, h0), hnorm2);
  final s = h[8];
  if (s == 0 || s.isNaN) return null;
  for (int i = 0; i < 9; i++) {
    h[i] /= s;
  }
  return h;
}

/// Eigenvector of the smallest eigenvalue of symmetric [a] (n x n, row-major)
/// by cyclic Jacobi rotations.
List<double> _smallestEigenvector(Float64List a0, int n) {
  final a = Float64List.fromList(a0);
  final v = Float64List(n * n);
  for (int i = 0; i < n; i++) {
    v[i * n + i] = 1;
  }
  for (int sweep = 0; sweep < 100; sweep++) {
    double off = 0;
    for (int p = 0; p < n; p++) {
      for (int q = p + 1; q < n; q++) {
        off += a[p * n + q] * a[p * n + q];
      }
    }
    if (off < 1e-30) break;
    for (int p = 0; p < n; p++) {
      for (int q = p + 1; q < n; q++) {
        final apq = a[p * n + q];
        if (apq.abs() < 1e-300) continue;
        final app = a[p * n + p], aqq = a[q * n + q];
        final theta = (aqq - app) / (2 * apq);
        final t = (theta >= 0 ? 1 : -1) /
            (theta.abs() + math.sqrt(theta * theta + 1));
        final c = 1 / math.sqrt(t * t + 1), s = t * c;
        for (int k = 0; k < n; k++) {
          final akp = a[k * n + p], akq = a[k * n + q];
          a[k * n + p] = c * akp - s * akq;
          a[k * n + q] = s * akp + c * akq;
        }
        for (int k = 0; k < n; k++) {
          final apk = a[p * n + k], aqk = a[q * n + k];
          a[p * n + k] = c * apk - s * aqk;
          a[q * n + k] = s * apk + c * aqk;
        }
        for (int k = 0; k < n; k++) {
          final vkp = v[k * n + p], vkq = v[k * n + q];
          v[k * n + p] = c * vkp - s * vkq;
          v[k * n + q] = s * vkp + c * vkq;
        }
      }
    }
  }
  int best = 0;
  for (int i = 1; i < n; i++) {
    if (a[i * n + i] < a[best * n + best]) best = i;
  }
  return [for (int k = 0; k < n; k++) v[k * n + best]];
}

/// Levenberg-Marquardt on the 8 free entries (h22 = 1) minimising the
/// squared distance between warped [src] and [dst], as OpenCV's
/// HomographyRefineCallback does after the DLT.
void _refineLM(Float64List h, List<Pt> src, List<Pt> dst, int maxIters) {
  final n = src.length;
  double err(Float64List hh) {
    double e = 0;
    for (int i = 0; i < n; i++) {
      final X = src[i].x, Y = src[i].y;
      final w = hh[6] * X + hh[7] * Y + 1;
      if (w == 0) return double.infinity;
      final dx = (hh[0] * X + hh[1] * Y + hh[2]) / w - dst[i].x;
      final dy = (hh[3] * X + hh[4] * Y + hh[5]) / w - dst[i].y;
      e += dx * dx + dy * dy;
    }
    return e;
  }

  double lambda = 1e-3;
  double cur = err(h);
  final jtj = Float64List(64),
      jte = Float64List(8),
      jx = Float64List(8),
      jy = Float64List(8);
  for (int it = 0; it < maxIters; it++) {
    jtj.fillRange(0, 64, 0);
    jte.fillRange(0, 8, 0);
    for (int i = 0; i < n; i++) {
      final X = src[i].x, Y = src[i].y;
      final w = h[6] * X + h[7] * Y + 1;
      final iw = 1 / w;
      final xi = (h[0] * X + h[1] * Y + h[2]) * iw;
      final yi = (h[3] * X + h[4] * Y + h[5]) * iw;
      jx
        ..[0] = X * iw
        ..[1] = Y * iw
        ..[2] = iw
        ..[3] = 0
        ..[4] = 0
        ..[5] = 0
        ..[6] = -X * xi * iw
        ..[7] = -Y * xi * iw;
      jy
        ..[0] = 0
        ..[1] = 0
        ..[2] = 0
        ..[3] = X * iw
        ..[4] = Y * iw
        ..[5] = iw
        ..[6] = -X * yi * iw
        ..[7] = -Y * yi * iw;
      final ex = xi - dst[i].x, ey = yi - dst[i].y;
      for (int a = 0; a < 8; a++) {
        jte[a] += jx[a] * ex + jy[a] * ey;
        for (int b = 0; b < 8; b++) {
          jtj[a * 8 + b] += jx[a] * jx[b] + jy[a] * jy[b];
        }
      }
    }
    bool improved = false;
    for (int tries = 0; tries < 10 && !improved; tries++) {
      final m = Float64List.fromList(jtj);
      for (int a = 0; a < 8; a++) {
        m[a * 8 + a] *= 1 + lambda;
      }
      final step = _solve(m, Float64List.fromList(jte), 8);
      if (step == null) break;
      final cand = Float64List.fromList(h);
      for (int a = 0; a < 8; a++) {
        cand[a] -= step[a];
      }
      final e = err(cand);
      if (e < cur) {
        h.setAll(0, cand);
        final rel = (cur - e) / math.max(cur, 1e-300);
        cur = e;
        lambda = math.max(lambda / 10, 1e-12);
        improved = true;
        if (rel < 1.1920929e-07) return;
      } else {
        lambda *= 10;
      }
    }
    if (!improved) return;
  }
}

/// Gaussian elimination with partial pivoting; null when singular.
Float64List? _solve(Float64List a, Float64List b, int n) {
  for (int c = 0; c < n; c++) {
    int p = c;
    for (int r = c + 1; r < n; r++) {
      if (a[r * n + c].abs() > a[p * n + c].abs()) p = r;
    }
    if (a[p * n + c].abs() < 1e-300) return null;
    if (p != c) {
      for (int k = 0; k < n; k++) {
        final t = a[c * n + k];
        a[c * n + k] = a[p * n + k];
        a[p * n + k] = t;
      }
      final t = b[c];
      b[c] = b[p];
      b[p] = t;
    }
    for (int r = c + 1; r < n; r++) {
      final f = a[r * n + c] / a[c * n + c];
      if (f == 0) continue;
      for (int k = c; k < n; k++) {
        a[r * n + k] -= f * a[c * n + k];
      }
      b[r] -= f * b[c];
    }
  }
  final x = Float64List(n);
  for (int r = n - 1; r >= 0; r--) {
    double s = b[r];
    for (int k = r + 1; k < n; k++) {
      s -= a[r * n + k] * x[k];
    }
    x[r] = s / a[r * n + r];
  }
  return x;
}

/// chesscog's `sort_corner_points`: [top left, top right, bottom right,
/// bottom left] — by y, then the top two by x and the bottom two by x
/// descending.
List<Pt> sortCornerPoints(List<Pt> pts) {
  final p = [...pts]..sort((a, b) => a.y.compareTo(b.y));
  final top = p.sublist(0, 2)..sort((a, b) => a.x.compareTo(b.x));
  final bottom = p.sublist(2, 4)..sort((a, b) => b.x.compareTo(a.x));
  return [...top, ...bottom];
}
