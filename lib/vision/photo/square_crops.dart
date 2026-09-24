/// Square crops for the photo classifiers, cut exactly as chesscog cuts them
/// (`chesscog/occupancy_classifier/create_dataset.py` and
/// `chesscog/piece_classifier/create_dataset.py`), so a model trained on
/// crops made by chesscog's Python (or tool/board_photo/py/crops.py, which
/// copies it) sees the same pixels here.
///
/// Squares are addressed in the image's own grid: row 0 is the rank of
/// squares farthest from the camera (the top of the photo), column 0 the
/// leftmost file. Mapping the grid to chess squares is the orientation
/// step's job (see board_photo_recognizer.dart) — chesscog instead asks the
/// user whether White or Black took the photo.
library;

import 'dart:typed_data';

import 'geometry.dart';
import 'image_ops.dart';

/// Warped-square side in both crops (chesscog's SQUARE_SIZE).
const int photoSquare = 50;

/// Occupancy crop: 100 x 100 (the square plus half a square all round).
const int occupancyCropSize = 2 * photoSquare;

/// Piece crop: 100 wide x 200 tall.
const int pieceCropWidth = 2 * photoSquare;
const int pieceCropHeight = 4 * photoSquare;

/// ImageNet normalisation (torchvision `Normalize`), which both classifiers
/// were trained with.
const List<double> imagenetMean = [0.485, 0.456, 0.406];
const List<double> imagenetStd = [0.229, 0.224, 0.225];

/// The board warped to a 500 x 500 image, 50 px squares and a one-square
/// margin (chesscog's occupancy `warp_chessboard_image`). [corners] are
/// image-order TL, TR, BR, BL.
RgbImage warpForOccupancy(RgbImage img, List<Pt> corners) =>
    _warpBoard(img, corners, photoSquare.toDouble(), 10 * photoSquare);

/// The board warped to an 800 x 800 image, 50 px squares and a four-square
/// margin (chesscog's piece `warp_chessboard_image`).
RgbImage warpForPieces(RgbImage img, List<Pt> corners) =>
    _warpBoard(img, corners, 4.0 * photoSquare, 16 * photoSquare);

RgbImage _warpBoard(RgbImage img, List<Pt> corners, double margin, int size) {
  final src = sortCornerPoints(corners);
  const b = 8.0 * photoSquare;
  final m = findHomography(src, [
    Pt(margin, margin),
    Pt(b + margin, margin),
    Pt(b + margin, b + margin),
    Pt(margin, b + margin),
  ]);
  if (m == null) throw StateError('degenerate board corners');
  final minv = mat3Inv(m);
  return RgbImage(size, size,
      warpPerspective(img.data, img.width, img.height, 3, minv, size, size));
}

/// The 100 x 100 RGB occupancy crop of grid cell ([row], [col]) from a
/// [warpForOccupancy] image: `img[50(row+.5) : 50(row+2.5), 50(col+.5) : ...]`.
Uint8List occupancyCrop(RgbImage warped, int row, int col) {
  const s = occupancyCropSize;
  final out = Uint8List(s * s * 3);
  final y0 = (photoSquare * (row + 0.5)).toInt();
  final x0 = (photoSquare * (col + 0.5)).toInt();
  for (int y = 0; y < s; y++) {
    final src = ((y0 + y) * warped.width + x0) * 3;
    out.setRange(y * s * 3, (y + 1) * s * 3, warped.data, src);
  }
  return out;
}

/// The 100 x 200 RGB piece crop of grid cell ([row], [col]) from a
/// [warpForPieces] image: the square plus 1 + 2 (7 - row) / 7 squares above
/// it (in the warped board a piece near the camera leans up over more
/// squares than a far one), plus 0.25..1 square sideways towards the board
/// edge, the left half mirrored so every piece leans the same way, pasted
/// bottom-left on black.
Uint8List pieceCrop(RgbImage warped, int row, int col) {
  const minH = 1.0, maxH = 3.0, minW = 0.25, maxW = 1.0;
  const margin = (16 * photoSquare - 8 * photoSquare) / 2; // 200
  final heightIncrease = minH + (maxH - minH) * ((7 - row) / 7);
  final leftIncrease = col >= 4 ? 0.0 : minW + (maxW - minW) * ((3 - col) / 3);
  final rightIncrease = col < 4 ? 0.0 : minW + (maxW - minW) * ((col - 4) / 3);
  final x1 = (margin + photoSquare * (col - leftIncrease)).toInt();
  final x2 = (margin + photoSquare * (col + 1 + rightIncrease)).toInt();
  final y1 = (margin + photoSquare * (row - heightIncrease)).toInt();
  final y2 = (margin + photoSquare * (row + 1)).toInt();
  final width = x2 - x1, height = y2 - y1;
  const ow = pieceCropWidth, oh = pieceCropHeight;
  final out = Uint8List(ow * oh * 3);
  final flip = col < 4;
  for (int y = 0; y < height; y++) {
    final oy = oh - height + y;
    for (int x = 0; x < width; x++) {
      final sx = flip ? x2 - 1 - x : x1 + x;
      final s = ((y1 + y) * warped.width + sx) * 3;
      final o = (oy * ow + x) * 3;
      out[o] = warped.data[s];
      out[o + 1] = warped.data[s + 1];
      out[o + 2] = warped.data[s + 2];
    }
  }
  return out;
}

/// Writes an RGB crop (w x h) as a normalised CHW float tensor into [out] at
/// [offset] — torchvision's `ToTensor()` + `Normalize(imagenet)`.
void cropToTensor(Uint8List rgb, int w, int h, Float32List out, int offset) {
  final n = w * h;
  for (int c = 0; c < 3; c++) {
    final m = imagenetMean[c], s = imagenetStd[c];
    final base = offset + c * n;
    for (int i = 0; i < n; i++) {
      out[base + i] = (rgb[i * 3 + c] / 255.0 - m) / s;
    }
  }
}
