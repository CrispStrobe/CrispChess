/// Low-level image operations for the photo board locator, written to match
/// the OpenCV calls chesscog makes (`cvtColor`, `resize`, `Sobel`, `Canny`,
/// `warpPerspective`) closely enough that the Dart port finds the same lines.
///
/// Plain Dart on typed lists — no Flutter, no FFI — so it runs everywhere the
/// app does, the web included, and is testable with `dart test`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// An 8-bit single-channel image, row-major.
class GrayU8 {
  final int width;
  final int height;
  final Uint8List px;

  GrayU8(this.width, this.height, [Uint8List? px])
      : px = px ?? Uint8List(width * height) {
    if (this.px.length != width * height) {
      throw ArgumentError('pixel buffer is not $width x $height');
    }
  }

  int at(int x, int y) => px[y * width + x];
}

/// An 8-bit RGB image, row-major, interleaved (R, G, B).
class RgbImage {
  final int width;
  final int height;
  final Uint8List data;

  RgbImage(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height * 3) {
    if (this.data.length != width * height * 3) {
      throw ArgumentError('pixel buffer is not $width x $height x 3');
    }
  }

  /// From RGBA (what `dart:ui`'s `rawRgba` gives). Alpha is dropped: a photo
  /// is opaque.
  factory RgbImage.fromRgba(Uint8List rgba, int width, int height) {
    if (rgba.length < width * height * 4) {
      throw ArgumentError('RGBA buffer holds fewer than $width x $height px');
    }
    final out = Uint8List(width * height * 3);
    for (int i = 0, j = 0; j < out.length; i += 4, j += 3) {
      out[j] = rgba[i];
      out[j + 1] = rgba[i + 1];
      out[j + 2] = rgba[i + 2];
    }
    return RgbImage(width, height, out);
  }

  /// Greyscale as OpenCV's `COLOR_BGR2GRAY` (14-bit fixed point).
  ///
  /// With [swapRedBlue] (the default) the buffer is read the way chesscog's
  /// recognition pipeline reads it: it hands an RGB image to a function that
  /// converts with `COLOR_BGR2GRAY`, so red gets blue's weight and vice
  /// versa. The locator's thresholds were tuned on exactly that.
  GrayU8 toGray({bool swapRedBlue = true}) {
    // OpenCV: B 1868, G 9617, R 4899 (sum 2^14), rounded.
    final wr = swapRedBlue ? 1868 : 4899;
    final wb = swapRedBlue ? 4899 : 1868;
    final g = Uint8List(width * height);
    for (int i = 0, j = 0; i < g.length; i++, j += 3) {
      g[i] =
          (data[j] * wr + data[j + 1] * 9617 + data[j + 2] * wb + 8192) >> 14;
    }
    return GrayU8(width, height, g);
  }
}

/// Bilinear resize with OpenCV's `INTER_LINEAR` sample positions
/// (pixel centres aligned: `src = (dst + 0.5) * scale - 0.5`, clamped).
///
/// [channels] is 1 or 3. With [antialias] and a shrink of 2x or more each
/// output pixel is instead the area average of its footprint (OpenCV's
/// `INTER_AREA`), which keeps a phone's 12-megapixel sensor noise from
/// aliasing into the edge map.
Uint8List resizeBilinear(
    Uint8List src, int sw, int sh, int dw, int dh, int channels,
    {bool antialias = false}) {
  final out = Uint8List(dw * dh * channels);
  final fx = sw / dw, fy = sh / dh;
  if (antialias && fx >= 2 && fy >= 2) {
    return _resizeArea(src, sw, sh, dw, dh, channels);
  }
  final x0 = Int32List(dw), x1 = Int32List(dw);
  final ax = Float64List(dw);
  for (int x = 0; x < dw; x++) {
    double s = (x + 0.5) * fx - 0.5;
    int i = s.floor();
    double a = s - i;
    if (i < 0) {
      i = 0;
      a = 0;
    }
    if (i >= sw - 1) {
      i = sw - 1;
      a = 0;
    }
    x0[x] = i * channels;
    x1[x] = math.min(i + 1, sw - 1) * channels;
    ax[x] = a;
  }
  for (int y = 0; y < dh; y++) {
    double s = (y + 0.5) * fy - 0.5;
    int i = s.floor();
    double b = s - i;
    if (i < 0) {
      i = 0;
      b = 0;
    }
    if (i >= sh - 1) {
      i = sh - 1;
      b = 0;
    }
    final r0 = i * sw * channels, r1 = math.min(i + 1, sh - 1) * sw * channels;
    int o = y * dw * channels;
    for (int x = 0; x < dw; x++) {
      final a = ax[x];
      for (int c = 0; c < channels; c++) {
        final top = src[r0 + x0[x] + c] * (1 - a) + src[r0 + x1[x] + c] * a;
        final bot = src[r1 + x0[x] + c] * (1 - a) + src[r1 + x1[x] + c] * a;
        out[o++] = (top * (1 - b) + bot * b + 0.5).toInt().clamp(0, 255);
      }
    }
  }
  return out;
}

Uint8List _resizeArea(
    Uint8List src, int sw, int sh, int dw, int dh, int channels) {
  final out = Uint8List(dw * dh * channels);
  final fx = sw / dw, fy = sh / dh;
  final acc = Float64List(channels);
  for (int y = 0; y < dh; y++) {
    final ya = y * fy, yb = (y + 1) * fy;
    final iya = ya.floor(), iyb = math.min(sh, yb.ceil());
    for (int x = 0; x < dw; x++) {
      final xa = x * fx, xb = (x + 1) * fx;
      final ixa = xa.floor(), ixb = math.min(sw, xb.ceil());
      acc.fillRange(0, channels, 0);
      double wsum = 0;
      for (int sy = iya; sy < iyb; sy++) {
        final wy = math.min(sy + 1.0, yb) - math.max(sy.toDouble(), ya);
        final row = sy * sw;
        for (int sx = ixa; sx < ixb; sx++) {
          final w = wy * (math.min(sx + 1.0, xb) - math.max(sx.toDouble(), xa));
          final p = (row + sx) * channels;
          for (int c = 0; c < channels; c++) {
            acc[c] += src[p + c] * w;
          }
          wsum += w;
        }
      }
      final o = (y * dw + x) * channels;
      for (int c = 0; c < channels; c++) {
        out[o + c] = (acc[c] / wsum + 0.5).toInt().clamp(0, 255);
      }
    }
  }
  return out;
}

/// Border handling for [sobel3].
enum Border { replicate, reflect101 }

int _borderIndex(int i, int n, Border b) {
  if (i >= 0 && i < n) return i;
  if (n == 1) return 0;
  if (b == Border.replicate) return i < 0 ? 0 : n - 1;
  // reflect101: -1 -> 1, n -> n-2
  return i < 0 ? -i : 2 * n - 2 - i;
}

/// 3x3 Sobel derivative (OpenCV `Sobel(..., ksize=3)`), exact integers.
/// [dx] true: d/dx ([-1 0 1] x [1 2 1]^T); false: d/dy.
Int32List sobel3(Uint8List src, int w, int h,
    {required bool dx, Border border = Border.reflect101}) {
  final out = Int32List(w * h);
  final xm = Int32List(w), xp = Int32List(w);
  for (int x = 0; x < w; x++) {
    xm[x] = _borderIndex(x - 1, w, border);
    xp[x] = _borderIndex(x + 1, w, border);
  }
  for (int y = 0; y < h; y++) {
    final rm = _borderIndex(y - 1, h, border) * w;
    final r0 = y * w;
    final rp = _borderIndex(y + 1, h, border) * w;
    for (int x = 0; x < w; x++) {
      final a = xm[x], c = xp[x];
      if (dx) {
        out[r0 + x] = (src[rm + c] - src[rm + a]) +
            2 * (src[r0 + c] - src[r0 + a]) +
            (src[rp + c] - src[rp + a]);
      } else {
        out[r0 + x] = (src[rp + a] + 2 * src[rp + x] + src[rp + c]) -
            (src[rm + a] + 2 * src[rm + x] + src[rm + c]);
      }
    }
  }
  return out;
}

/// Canny edge detector as OpenCV implements it for `apertureSize == 3`,
/// `L2gradient == false`: Sobel with replicated borders, L1 magnitude,
/// non-maximum suppression in four directions with OpenCV's asymmetric
/// comparisons, hysteresis over 8-connected neighbours. Returns 0/255.
Uint8List canny(
    Uint8List src, int w, int h, double lowThresh, double highThresh) {
  if (lowThresh > highThresh) {
    final t = lowThresh;
    lowThresh = highThresh;
    highThresh = t;
  }
  final low = lowThresh.floor(), high = highThresh.floor();
  final gx = sobel3(src, w, h, dx: true, border: Border.replicate);
  final gy = sobel3(src, w, h, dx: false, border: Border.replicate);
  // Magnitude with a zero border one pixel wide all round.
  final mw = w + 2;
  final mag = Int32List(mw * (h + 2));
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final i = y * w + x;
      mag[(y + 1) * mw + x + 1] = gx[i].abs() + gy[i].abs();
    }
  }
  // 0: candidate, 1: not an edge, 2: edge. Same one-pixel border (= 1).
  final map = Uint8List(mw * (h + 2))..fillRange(0, mw * (h + 2), 1);
  final stack = <int>[];
  const tg22 = 13573; // tan(22.5 deg) * 2^15
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final j = (y + 1) * mw + x + 1;
      final m = mag[j];
      if (m <= low) continue; // stays 1
      final i = y * w + x;
      final xs = gx[i], ys = gy[i];
      final ax = xs.abs();
      final ay = ys.abs() << 15;
      final tg22x = ax * tg22;
      bool keep;
      if (ay < tg22x) {
        keep = m > mag[j - 1] && m >= mag[j + 1];
      } else {
        final tg67x = tg22x + (ax << 16);
        if (ay > tg67x) {
          keep = m > mag[j - mw] && m >= mag[j + mw];
        } else {
          final s = (xs ^ ys) < 0 ? -1 : 1;
          keep = m > mag[j - mw - s] && m > mag[j + mw + s];
        }
      }
      if (!keep) continue;
      if (m > high) {
        map[j] = 2;
        stack.add(j);
      } else {
        map[j] = 0;
      }
    }
  }
  final nbr =
      Int32List.fromList([-mw - 1, -mw, -mw + 1, -1, 1, mw - 1, mw, mw + 1]);
  while (stack.isNotEmpty) {
    final j = stack.removeLast();
    for (int k = 0; k < 8; k++) {
      final q = j + nbr[k];
      if (map[q] == 0) {
        map[q] = 2;
        stack.add(q);
      }
    }
  }
  final out = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (map[(y + 1) * mw + x + 1] == 2) out[y * w + x] = 255;
    }
  }
  return out;
}

/// `warpPerspective(src, M, (dw, dh))` with bilinear interpolation and a
/// constant zero border: dst(x, y) = src(M^-1 (x, y)). [minv] is the inverse
/// of the source-to-destination homography, row-major 3x3. Sample positions
/// are quantised to 1/32 pixel as OpenCV's fixed-point remap does.
Uint8List warpPerspective(Uint8List src, int sw, int sh, int channels,
    Float64List minv, int dw, int dh) {
  final out = Uint8List(dw * dh * channels);
  for (int y = 0; y < dh; y++) {
    for (int x = 0; x < dw; x++) {
      final wz = minv[6] * x + minv[7] * y + minv[8];
      if (wz == 0) continue;
      final w = 1 / wz;
      final fx = (minv[0] * x + minv[1] * y + minv[2]) * w;
      final fy = (minv[3] * x + minv[4] * y + minv[5]) * w;
      // OpenCV clamps to int range, then rounds to 1/32 px.
      if (fx.isNaN || fy.isNaN || fx.abs() > 1e8 || fy.abs() > 1e8) continue;
      final qx = (fx * 32).round(), qy = (fy * 32).round();
      final ix = qx >> 5, iy = qy >> 5;
      final ax = (qx & 31) / 32, ay = (qy & 31) / 32;
      if (ix < -1 || iy < -1 || ix >= sw || iy >= sh) continue;
      final o = (y * dw + x) * channels;
      final in00 = ix >= 0 && iy >= 0;
      final in10 = ix + 1 < sw && iy >= 0;
      final in01 = ix >= 0 && iy + 1 < sh;
      final in11 = ix + 1 < sw && iy + 1 < sh;
      final w00 = (1 - ax) * (1 - ay), w10 = ax * (1 - ay);
      final w01 = (1 - ax) * ay, w11 = ax * ay;
      for (int c = 0; c < channels; c++) {
        double v = 0;
        if (in00) v += src[(iy * sw + ix) * channels + c] * w00;
        if (in10) v += src[(iy * sw + ix + 1) * channels + c] * w10;
        if (in01) v += src[((iy + 1) * sw + ix) * channels + c] * w01;
        if (in11) v += src[((iy + 1) * sw + ix + 1) * channels + c] * w11;
        out[o + c] = (v + 0.5).toInt().clamp(0, 255);
      }
    }
  }
  return out;
}
