"""Square crops exactly as chesscog cuts them, addressed by image grid cell.

Mirrors chesscog/occupancy_classifier/create_dataset.py and
chesscog/piece_classifier/create_dataset.py (MIT) and, on the Dart side,
lib/vision/photo/square_crops.dart. Grid cell (row, col): row 0 is the top of
the photo, col 0 its left; chesscog's `turn` argument maps chess squares to
these cells, here the caller does.

Also holds the resize both sides agree on (1200 px wide; area averaging when
shrinking 2x or more, bilinear otherwise) and the grid <-> FEN helpers.
"""
import numpy as np
import cv2

SQUARE_SIZE = 50
BOARD_SIZE = 8 * SQUARE_SIZE
OCC_IMG = BOARD_SIZE + 2 * SQUARE_SIZE           # 500
PIECE_IMG = BOARD_SIZE * 2                        # 800
PIECE_MARGIN = (PIECE_IMG - BOARD_SIZE) / 2       # 200
OUT_W, OUT_H = 2 * SQUARE_SIZE, 4 * SQUARE_SIZE   # 100 x 200
PIECES = "bknpqrBKNPQR"   # chesscog's class order: black_bishop .. white_rook
MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)


def resize_for_locator(rgb, width=1200):
    h, w = rgb.shape[:2]
    if w == width:
        return rgb, 1.0
    s = width / w
    nh = int(h * s)
    interp = cv2.INTER_AREA if w >= 2 * width else cv2.INTER_LINEAR
    return cv2.resize(rgb, (width, nh), interpolation=interp), s


def sort_corner_points(points):
    points = np.array(points, np.float32)
    points = points[points[:, 1].argsort()]
    points[:2] = points[:2][points[:2, 0].argsort()]
    points[2:] = points[2:][points[2:, 0].argsort()[::-1]]
    return points


def _warp(img, corners, margin, size):
    src = sort_corner_points(corners)
    dst = np.array([[margin, margin], [BOARD_SIZE + margin, margin],
                    [BOARD_SIZE + margin, BOARD_SIZE + margin],
                    [margin, BOARD_SIZE + margin]], np.float32)
    m, _ = cv2.findHomography(src, dst)
    return cv2.warpPerspective(img, m, (size, size))


def warp_occupancy(img, corners):
    return _warp(img, corners, SQUARE_SIZE, OCC_IMG)


def warp_pieces(img, corners):
    return _warp(img, corners, PIECE_MARGIN, PIECE_IMG)


def occupancy_crop(warped, row, col):
    return warped[int(SQUARE_SIZE * (row + .5)): int(SQUARE_SIZE * (row + 2.5)),
                  int(SQUARE_SIZE * (col + .5)): int(SQUARE_SIZE * (col + 2.5))]


def piece_crop(warped, row, col):
    height_increase = 1 + 2 * ((7 - row) / 7)
    left_increase = 0 if col >= 4 else .25 + .75 * ((3 - col) / 3)
    right_increase = 0 if col < 4 else .25 + .75 * ((col - 4) / 3)
    x1 = int(PIECE_MARGIN + SQUARE_SIZE * (col - left_increase))
    x2 = int(PIECE_MARGIN + SQUARE_SIZE * (col + 1 + right_increase))
    y1 = int(PIECE_MARGIN + SQUARE_SIZE * (row - height_increase))
    y2 = int(PIECE_MARGIN + SQUARE_SIZE * (row + 1))
    crop = warped[y1:y2, x1:x2]
    if col < 4:
        crop = cv2.flip(crop, 1)
    out = np.zeros((OUT_H, OUT_W, 3), dtype=crop.dtype)
    out[OUT_H - (y2 - y1):, :x2 - x1] = crop
    return out


def to_tensor(crops):
    """uint8 NHWC -> float32 NCHW, ImageNet-normalised."""
    x = crops.astype(np.float32) / 255.0
    x = (x - MEAN) / STD
    return np.ascontiguousarray(x.transpose(0, 3, 1, 2))


def fen_to_chess64(fen):
    """Board part of a FEN -> 64 chars, a8..h8, ..., a1..h1, '.' empty."""
    out = []
    fen = fen.split(" ")[0].split("_")[0]  # samryan names duplicates "<fen>_2"
    for row in fen.replace("-", "/").split("/"):
        for ch in row:
            out.extend("." * int(ch) if ch.isdigit() else ch)
    assert len(out) == 64, fen
    return "".join(out)


def grid_index_for(i, rotation):
    """Grid cell holding chess square i (0 = a8) under `rotation` quarter turns
    (as BoardPhotoResult.gridIndexFor in Dart)."""
    r, c = divmod(i, 8)
    rotation %= 4
    if rotation == 0:
        return r * 8 + c
    if rotation == 2:
        return (7 - r) * 8 + (7 - c)
    if rotation == 1:
        return (7 - c) * 8 + r
    return c * 8 + (7 - r)


def chess_to_grid(chess64, rotation):
    g = ["."] * 64
    for i in range(64):
        g[grid_index_for(i, rotation)] = chess64[i]
    return "".join(g)
