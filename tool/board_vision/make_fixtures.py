"""Render the board images test/board_vision_test.dart recognizes.

    python3 tool/board_vision/make_fixtures.py

Writes test/fixtures/board_vision/*.png plus expected.json. Deterministic
(for a given Pillow and set of fonts).
The positions and renderings are new to the model; the piece styles are not
(the shipped model trains on every permissive source). How the model does on
a piece set it never saw is measured by train.py --holdout on bench.py boards.
"""

import json
import os
import random
import sys

import numpy as np

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import render as R  # noqa: E402

OUT = os.path.join(R.ROOT, 'test', 'fixtures', 'board_vision')

CASES = [
    # name, fen, set, style, cell, margin, flipped, embed-in-screenshot
    ('screen_chessnut',
     'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R', 'chessnut',
     'screen', 48, 14, False, False),
    ('book_noto',
     '2r3k1/pp3ppp/4p3/3pP3/3P4/P4N2/1P3PPP/2R3K1', 'font-noto-symbols2',
     'book', 44, 26, False, False),
    ('flipped_dejavu',
     'r4rk1/1bq1bppp/p2ppn2/1p6/3NP3/1BN1B3/PPP1QPPP/2KR3R', 'font-dejavu',
     'screen', 46, 10, True, False),
    ('screenshot_papercut',
     '8/5pk1/6p1/2R5/5P2/6KP/r7/8', 'papercut',
     'screen', 40, 0, False, True),
]

# Harder captures, each through render.capture with a fixed seed:
# name, fen, set, style, cell, seed, lowres
CAPTURED = [
    # A small print diagram with coordinates, scanned low and zoomed.
    ('lowres_book_juliamono',
     'r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N2N2/PP2BPPP/R2QKB1R',
     'font-juliamono', 'book', 20, 7, True),
    ('photo_firi',
     '6k1/5ppp/8/3Q4/8/8/5PPP/3r2K1', 'firi', 'screen', 44, 3, False),
]


def embed(board_img, rng):
    """Put the board off-centre in a fake app screenshot: bars, text, buttons."""
    bw, bh = board_img.size
    W, H = bw + 90, bh + 260
    img = Image.new('RGB', (W, H), (38, 36, 33))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(R.FONT_SETS['font-dejavu'], 16)
    d.rectangle([0, 0, W, 48], fill=(22, 21, 18))
    d.text((12, 14), 'Opponent (1843)   5:12', font=font, fill=(230, 230, 230))
    img.paste(board_img, (30, 70))
    y = 70 + bh + 16
    d.text((12, y), 'You (1790)   4:58', font=font, fill=(230, 230, 230))
    for i in range(4):
        d.rounded_rectangle([12 + i * 80, y + 40, 80 + i * 80, y + 80], 8,
                            fill=(70, 68, 64))
    d.text((12, y + 100), '1. e4 c5 2. Nf3 d6 3. d4 cxd4', font=font,
           fill=(200, 200, 200))
    return img


def capture_fixed(img, rect, rng, style, lowres):
    """render.capture, retried until it actually rotates or skews the board
    (for the photo) — the point of these fixtures is the damage."""
    while True:
        state = rng.getstate()
        out = R.capture(img, rect, rng, style, lowres=lowres)
        x0, y0, cw, ch = out[1]
        if lowres or abs(cw - rect[2]) > 0.3 or abs(ch - rect[2]) > 0.3:
            return out
        rng.setstate(state)
        rng.random()


# The front board of `two_diagrams`.
TWO_FRONT = 'r2q1rk1/pp1bbppp/2n1pn2/3p4/3P4/2NBPN2/PP3PPP/R2Q1RK1'


def two_diagrams():
    """A screen board overlapping a hatched book diagram of larger squares,
    as when one diagram is pasted over a scanned page: seven lines of the
    front board plus the back board's edge also make a lattice."""
    rng = random.Random(42)
    back, (bx, by, _) = R.render_board(
        R.fen_to_placement('8/8/8/8/8/8/8/8'), 'chessnut', rng, cell=26,
        style='book', margin=4, hatch=True, extras=False)
    front, (fx, fy, cell) = R.render_board(
        R.fen_to_placement(TWO_FRONT), 'chessnut', rng, cell=26,
        style='screen', margin=3)
    # The back board's first file stays visible, one square wide and in
    # step with the front board's rows.
    x, y = bx + 26 - fx, by - fy
    img = Image.new('RGB', (x + front.width, max(back.height, y + front.height)),
                    'white')
    img.paste(back, (0, 0))
    img.paste(front, (x, y))
    return img


# Cells whose 32x32 network input the Dart test recomputes: fixture,
# (x0, y0, w, h) in source pixels. Fractional, off-grid and non-square on
# purpose — the preprocessing contract, not the board, is under test.
PARITY = [
    ('screen_chessnut', (14.0, 14.0, 48.0, 48.0)),
    ('photo_firi', (20.37, 27.61, 43.19, 43.33)),
    ('lowres_book_juliamono', (33.9, 51.8, 39.5, 30.2)),
    ('book_noto', (-3.5, 400.25, 47.75, 60.0)),
]


def write_parity():
    """parity.json: per cell, the sum, the sum of squares and eight
    samples of render.cell_to_input, for test/board_vision_test.dart."""
    out = []
    for name, (x0, y0, w, h) in PARITY:
        gray = R.grayscale(Image.open(os.path.join(OUT, f'{name}.png')))
        cell = R.cell_to_input(gray, x0, y0, w, h).astype(np.float64)
        out.append({'fixture': name, 'rect': [x0, y0, w, h],
                    'sum': float(cell.sum()),
                    'sumSq': float((cell * cell).sum()),
                    'samples': [[i, j, float(cell[i, j])] for i, j in
                                [(0, 0), (0, 31), (31, 0), (31, 31), (5, 17),
                                 (16, 16), (22, 3), (9, 28)]]})
    with open(os.path.join(OUT, 'parity.json'), 'w') as f:
        json.dump(out, f, indent=1)


def main():
    os.makedirs(OUT, exist_ok=True)
    expected = {}
    for i, (name, fen, set_name, style, cell, margin, flipped, emb) in \
            enumerate(CASES):
        rng = random.Random(100 + i)
        board = R.fen_to_placement(fen)
        img, _ = R.render_board(board, set_name, rng, cell=cell, style=style,
                                flipped=flipped, margin=margin,
                                hatch=True if style == 'book' else None)
        if emb:
            img = embed(img, rng)
        img.save(os.path.join(OUT, f'{name}.png'), optimize=True)
        expected[name] = {'placement': fen, 'flipped': flipped}
    for name, fen, set_name, style, cell, seed, lowres in CAPTURED:
        rng = random.Random(seed)
        board = R.fen_to_placement(fen)
        img, rect = R.render_board(board, set_name, rng, cell=cell,
                                   style=style, margin=cell // 2, extras=True)
        img, _ = capture_fixed(img, rect, rng, style, lowres)
        img.save(os.path.join(OUT, f'{name}.png'), optimize=True)
        expected[name] = {'placement': fen, 'flipped': False}
    img = two_diagrams()
    img.save(os.path.join(OUT, 'two_diagrams.png'), optimize=True)
    expected['two_diagrams'] = {'placement': TWO_FRONT, 'flipped': False}
    write_parity()
    with open(os.path.join(OUT, 'expected.json'), 'w') as f:
        json.dump(expected, f, indent=2)
    print('wrote', len(expected), 'fixtures and parity.json to', OUT)


if __name__ == '__main__':
    main()
