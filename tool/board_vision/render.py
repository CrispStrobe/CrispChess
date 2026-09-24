"""Synthetic chess-board rendering and the square preprocessing contract.

Shared by gen.py (training data), bench.py and make_fixtures.py (test
boards), so the network is trained on exactly what
lib/vision/board_recognizer.dart feeds it.

Preprocessing contract (mirrored in Dart, keep the two in sync):
  1. grayscale  g = (299*R + 587*G + 114*B) / 1000, on 0..255
  2. a square cell [x0, x1) x [y0, y1) (float bounds) is resampled to 32x32 by
     area averaging: output pixel (i, j) is the mean of the source pixels
     x in [floor(x0 + j*w/32), max(that+1, floor(x0 + (j+1)*w/32))), likewise y
     — see `cell_to_input`
  3. value / 255 -> float32 in [0, 1], layout [N, 1, 32, 32]

Two looks are rendered: 'screen' (flat coloured squares, as apps and sites
draw them) and 'book' (ink on paper: hatched, stippled, screened or grey dark
squares, coordinates and a frame around the board). `capture` then adds what
getting the picture into the app does to it: low resolution, slight rotation
and perspective, uneven light, paper, ink spread, halftone, blur, noise, JPEG.
"""

import io
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PIECE_DIR = os.path.join(ROOT, 'assets', 'pieces')
# Training-only piece sets that are not app assets.
EXTRA_PIECE_DIR = os.path.join(os.path.dirname(__file__), 'pieces')
# Optional directory of pre-rendered <set>/<w|b><K..P>.png (see
# prerender.py): lets the generator run where cairosvg is not installed.
PNG_PIECE_DIR = os.environ.get('BV_PIECE_PNG')

INPUT = 32
# Class order — index i is the network's output i. Mirrored in Dart.
CLASSES = ['.', 'P', 'N', 'B', 'R', 'Q', 'K', 'p', 'n', 'b', 'r', 'q', 'k']

SVG_SETS = ['celtic', 'chessnut', 'fantasy', 'kiwen-suwi', 'papercut',
            'rhosgfx', 'spatial', 'totoy', 'firi']
# Glyph fonts for Unicode chess pieces. Permissive licences only — the
# shipped model must be trainable from permissively licensed sources (see
# README "Training data licences"). GNU FreeFont (GPL only) was tried and
# dropped for that reason; Unifont is used under its OFL option.
FONT_DIR = os.path.join(os.path.dirname(__file__), 'fonts')
_DEJAVU = os.environ.get('BV_DEJAVU_DIR', '/usr/share/fonts/truetype/dejavu')
FONT_SETS = {
    # Bitstream Vera licence (DejaVu changes public domain). Sans and Sans
    # Bold share one piece design; Bold adds stroke weight.
    'font-dejavu': os.path.join(_DEJAVU, 'DejaVuSans.ttf'),
    'font-dejavu-bold': os.path.join(_DEJAVU, 'DejaVuSans-Bold.ttf'),
    # SIL OFL 1.1 — fetched by fonts/fetch.sh.
    'font-noto-symbols2': os.path.join(FONT_DIR, 'NotoSansSymbols2-Regular.ttf'),
    'font-juliamono': os.path.join(FONT_DIR, 'JuliaMono-Regular.ttf'),
    'font-fairfax-hd': os.path.join(FONT_DIR, 'FairfaxHD.ttf'),
    'font-unifont': os.path.join(FONT_DIR, 'unifont-15.1.05.otf'),
}
# Text fonts for coordinates and captions (Bitstream Vera licence).
LABEL_FONTS = [os.path.join(_DEJAVU, f) for f in (
    'DejaVuSans.ttf', 'DejaVuSans-Bold.ttf', 'DejaVuSerif.ttf',
    'DejaVuSerif-Bold.ttf')]

# (light, dark) square colours: the app's own themes plus the usual sites'.
THEMES = [
    ((0xF0, 0xD9, 0xB5), (0xB5, 0x88, 0x63)),
    ((0xEE, 0xEE, 0xD2), (0x76, 0x96, 0x56)),
    ((0xDE, 0xE3, 0xE6), (0x8C, 0xA2, 0xAD)),
    ((0xD9, 0xD9, 0xD9), (0x8B, 0x8B, 0x8B)),
    ((0xC8, 0xE6, 0xC9), (0x38, 0x8E, 0x3C)),
    ((0xE0, 0xC8, 0xA8), (0x8B, 0x6B, 0x47)),
    ((0xF0, 0xF4, 0xF8), (0x9B, 0xB8, 0xD3)),
    ((0xC4, 0xCC, 0xD8), (0x4B, 0x65, 0x84)),
    ((0xEB, 0xEC, 0xD0), (0x73, 0x95, 0x52)),  # chess.com green
    ((0xEA, 0xE9, 0xD2), (0x4B, 0x73, 0x99)),  # chess.com blue
    ((0xFF, 0xCE, 0x9E), (0xD1, 0x8B, 0x47)),  # classic brown
    ((0xE8, 0xED, 0xF9), (0xB7, 0xC0, 0xD8)),  # pale blue
    ((0xFF, 0xFF, 0xFF), (0xC0, 0xC0, 0xC0)),  # print grey
    ((0xFF, 0xFF, 0xFF), (0xE8, 0xE8, 0xE8)),  # pale print grey (PDFs)
    ((0xF4, 0xF4, 0xF4), (0xDC, 0xDC, 0xDC)),
]

_piece_cache = {}

# The shipped model's recipe is the default. BV_EXTRA_AUG=1 adds what was
# tried on top of it and did not beat it on the synthetic benchmarks (see
# the README): per-type piece sizes and shape warps, restyled screen pieces
# with shadows, grey book pieces, and the ink-threshold fixes for firi and
# rhosgfx.
EXTRA = os.environ.get('BV_EXTRA_AUG') == '1'


def _svg_path(set_name, code):
    color = 'w' if code.isupper() else 'b'
    name = f'{color}{code.upper()}.svg'
    for base in (PIECE_DIR, EXTRA_PIECE_DIR):
        path = os.path.join(base, set_name, name)
        if os.path.exists(path):
            return path
    raise FileNotFoundError(f'{set_name}/{name}')


def _svg_piece(set_name, code, px):
    color = 'w' if code.isupper() else 'b'
    if PNG_PIECE_DIR:
        path = os.path.join(PNG_PIECE_DIR, set_name, f'{color}{code.upper()}.png')
        return Image.open(path).convert('RGBA').resize((px, px), Image.LANCZOS)
    import cairosvg
    png = cairosvg.svg2png(url=_svg_path(set_name, code), output_width=px,
                           output_height=px)
    return Image.open(io.BytesIO(png)).convert('RGBA')


# Unicode chess glyphs: outline (white) U+2654.., filled (black) U+265A..
_GLYPH = {'K': 0, 'Q': 1, 'R': 2, 'B': 3, 'N': 4, 'P': 5}


def _font_piece(font_path, code, px):
    font = ImageFont.truetype(font_path, int(px * 0.9))
    img = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    filled = chr(0x265A + _GLYPH[code.upper()])
    outline = chr(0x2654 + _GLYPH[code.upper()])
    bbox = d.textbbox((0, 0), filled, font=font)
    ox = (px - (bbox[2] - bbox[0])) / 2 - bbox[0]
    oy = (px - (bbox[3] - bbox[1])) / 2 - bbox[1]
    if code.isupper():
        # White piece: the filled silhouette painted white, the outline on top.
        # The pawn's filled glyph is sometimes emoji-presented; the silhouette
        # still gives the right body.
        d.text((ox, oy), filled, font=font, fill=(255, 255, 255, 255))
        d.text((ox, oy), outline, font=font, fill=(0, 0, 0, 255))
    else:
        d.text((ox, oy), filled, font=font, fill=(0, 0, 0, 255))
    return img


def piece_image(set_name, code, px=128):
    key = (set_name, code, px)
    if key not in _piece_cache:
        if set_name in FONT_SETS:
            _piece_cache[key] = _font_piece(FONT_SETS[set_name], code, px)
        else:
            _piece_cache[key] = _svg_piece(set_name, code, px)
    return _piece_cache[key]


def random_placement(rng, density=None):
    """8x8 list of class chars ('.' empty), rank 8 first like a FEN."""
    density = rng.uniform(0.15, 0.7) if density is None else density
    board = [['.'] * 8 for _ in range(8)]
    for r in range(8):
        for c in range(8):
            if rng.random() < density:
                board[r][c] = rng.choice(CLASSES[1:])
    return board


def placement_to_fen(board):
    rows = []
    for row in board:
        s, run = '', 0
        for ch in row:
            if ch == '.':
                run += 1
            else:
                if run:
                    s += str(run)
                    run = 0
                s += ch
        if run:
            s += str(run)
        rows.append(s)
    return '/'.join(rows)


def fen_to_placement(fen):
    board = []
    for row in fen.split(' ')[0].split('/'):
        r = []
        for ch in row:
            r.extend(['.'] * int(ch) if ch.isdigit() else [ch])
        board.append(r)
    return board


def _nrng(rng):
    return np.random.default_rng(rng.randrange(1 << 30))


def _dark_pattern(w, h, cell, rng):
    """Print dark-square fill for a w x h area: 0 = ink, 255 = paper.

    Drawn over the whole board at 3x and area-downsampled, so thin lines come
    out as the grey, anti-aliased strokes a scanner produces. One pattern per
    board, like a printer's: diagonal hatching (the usual), cross-hatching,
    horizontal or vertical lines, stipple, a halftone dot screen, an ordered
    dither, or flat grey.
    """
    kind = rng.choices(
        ['diag', 'cross', 'lines', 'stipple', 'dots', 'dither', 'grey'],
        [0.46, 0.08, 0.08, 0.1, 0.1, 0.06, 0.12])[0]
    if kind == 'grey':
        g = rng.randint(120, 225)
        return np.full((h, w), g, np.uint8), kind
    if kind == 'dither':
        # Checker / Bayer ordered dither of a mid grey, as early DTP did.
        level = rng.uniform(0.3, 0.6)
        bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9],
                          [15, 7, 13, 5]]) / 16 + 1 / 32
        dot = rng.choice([1, 1, 2])
        tile = np.kron(bayer, np.ones((dot, dot)))
        reps = (h // tile.shape[0] + 1, w // tile.shape[1] + 1)
        return np.where(np.tile(tile, reps)[:h, :w] < level, 0, 255
                        ).astype(np.uint8), kind
    if kind == 'stipple':
        nr = _nrng(rng)
        dens = rng.uniform(0.15, 0.45)
        grain = rng.choice([1, 1, 2])
        m = nr.random((h // grain + 1, w // grain + 1)) < dens
        m = np.kron(m, np.ones((grain, grain), bool))[:h, :w]
        return np.where(m, 0, 255).astype(np.uint8), kind
    s = 3
    W, H = w * s, h * s
    img = Image.new('L', (W, H), 255)
    d = ImageDraw.Draw(img)
    if kind == 'dots':
        pitch = cell * rng.uniform(0.07, 0.16) * s
        rad = pitch * rng.uniform(0.25, 0.45)
        y = 0.0
        row = 0
        while y < H + pitch:
            x = (pitch / 2) * (row % 2)
            while x < W + pitch:
                d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=0)
                x += pitch
            y += pitch * 0.87
            row += 1
    else:
        pitch = max(cell * rng.uniform(0.055, 0.16), 2.2) * s
        width = max(1, int(round(pitch * rng.uniform(0.2, 0.55))))
        if kind == 'diag':
            angles = [rng.choice([45, 45, 45, 135, 60, 30, 120])]
        elif kind == 'cross':
            a = rng.choice([45, 0])
            angles = [a, a + 90]
        else:
            angles = [rng.choice([0, 0, 90])]
        for ang in angles:
            t = math.radians(ang)
            # Lines x*sin(t) - y*cos(t) = k*pitch, clipped by drawing long.
            dx, dy = math.cos(t), math.sin(t)
            nx, ny = -dy, dx
            L = W + H
            k = -L
            while k < L:
                cx, cy = W / 2 + nx * k, H / 2 + ny * k
                d.line([(cx - dx * L, cy - dy * L), (cx + dx * L, cy + dy * L)],
                       fill=0, width=width)
                k += pitch
    arr = np.asarray(img.resize((w, h), Image.BOX))
    return arr, kind


def _ink_piece(p, rng, threshold=None):
    """Print look: a piece as black ink on white fill, as an L image + mask."""
    arr = np.asarray(p).astype(np.float32)
    lum = arr[..., :3] @ np.array([0.299, 0.587, 0.114])
    thr = rng.uniform(95, 165) if threshold is None else threshold
    ink = np.where(lum < thr, 0, 255).astype(np.uint8)
    return Image.fromarray(ink, 'L'), Image.fromarray(arr[..., 3].astype(np.uint8))


def _text_font(rng, size):
    try:
        return ImageFont.truetype(rng.choice(LABEL_FONTS), max(6, int(size)))
    except OSError:
        return ImageFont.load_default()


_WORDS = ('White to move Black wins draw after the exchange position diagram '
          'Kasparov Karpov Nimzowitsch 1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 16...Qxf2+ '
          'Rk. Kt. Bp. Q. K. BLACK WHITE Fig. 12 Exercise solution threat '
          'the knight on c3 cannot move because').split()


def _caption(rng, n):
    return ' '.join(rng.choice(_WORDS) for _ in range(n))


def render_board(board, set_name, rng, cell=None, style=None, flipped=False,
                 margin=0, hatch=None, extras=None):
    """Render a board. Returns (RGB image, (x0, y0, cell_px)).

    `margin` is the minimum space around the board; 'book' boards with
    coordinates or captions (`extras`, random when None) get more. `hatch`
    forces textured (True) or flat grey (False) dark squares on 'book'.
    """
    cell = cell or rng.randint(22, 90)
    if flipped:
        # Seen from Black's side: the arrangement turns 180 degrees, the
        # pieces themselves stay upright.
        board = [row[::-1] for row in board[::-1]]
    style = style or ('book' if rng.random() < 0.45 else 'screen')
    if style == 'book':
        return _render_book(board, set_name, rng, cell, margin, hatch, extras)
    return _render_screen(board, set_name, rng, cell, margin, extras)


def _piece_px(cell, rng, scale=None):
    scale = rng.uniform(0.8, 1.0) if scale is None else scale
    return max(6, int(round(cell * scale)))


def _type_sizes(px, cell, rng):
    """Pixel size per piece type for one board. Sets differ in how big they
    draw each piece against the others (a large pawn in one font is the size
    of a bishop in another), so the relative size must not be a cue."""
    if rng.random() < 0.4:
        return {t: px for t in 'KQRBNP'}
    return {t: max(6, min(cell, int(round(px * rng.uniform(0.85, 1.2)))))
            for t in 'KQRBNP'}


def _restyle(p, lo, hi, shadow):
    """A screen piece redrawn between grey levels lo (its darkest) and hi
    (its lightest) — themes that draw black pieces dark grey, washed-out
    captures — optionally over a soft drop shadow."""
    arr = np.asarray(p).astype(np.float32)
    if lo is not None:
        lum = arr[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32) / 255
        arr[..., :3] = (lo + (hi - lo) * lum)[..., None]
    out = Image.fromarray(arr.astype(np.uint8), 'RGBA')
    if shadow:
        a = out.getchannel('A').filter(ImageFilter.GaussianBlur(max(1, p.width / 30)))
        sh = Image.new('RGBA', out.size, (0, 0, 0, 0))
        off = max(1, p.width // 25)
        sh.paste(Image.new('RGBA', out.size, (0, 0, 0, 255)), (off, off),
                 a.point(lambda v: v * 0.5))
        out = Image.alpha_composite(sh, out)
    return out


def _render_screen(board, set_name, rng, cell, margin, extras):
    size = cell * 8
    light, dark = rng.choice(THEMES)
    jitter = lambda c: tuple(max(0, min(255, v + rng.randint(-12, 12))) for v in c)
    light, dark = jitter(light), jitter(dark)
    bg = tuple(rng.randint(20, 240) for _ in range(3))
    img = Image.new('RGB', (size + 2 * margin, size + 2 * margin), bg)
    ox = oy = margin
    highlight = None
    if rng.random() < 0.5:
        highlight = [(rng.randrange(8), rng.randrange(8)) for _ in range(2)]
        hl = rng.choice([(247, 247, 105), (187, 203, 43), (205, 210, 106),
                         (170, 162, 58), (155, 199, 0), (130, 151, 105)])
    d = ImageDraw.Draw(img)
    for r in range(8):
        for c in range(8):
            is_dark = (r + c) % 2 == 1
            x, y = ox + c * cell, oy + r * cell
            col = dark if is_dark else light
            if highlight and (r, c) in highlight:
                a = rng.uniform(0.4, 0.8)
                col = tuple(int(col[i] * (1 - a) + hl[i] * a) for i in range(3))
            d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=col)
    if rng.random() < 0.15:
        # Wood-like or marble-like texture over the squares.
        nr = _nrng(rng)
        k = rng.choice([4, 8, 16])
        field = nr.normal(0, 1, (k, k * rng.choice([1, 4])))
        field = np.asarray(Image.fromarray(field.astype(np.float32), 'F')
                           .resize((size, size), Image.BICUBIC))
        arr = np.asarray(img).astype(np.float32)
        arr[oy:oy + size, ox:ox + size] += field[..., None] * rng.uniform(4, 14)
        img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
        d = ImageDraw.Draw(img)
    # Coordinates drawn inside the edge squares, as lichess/chess.com do.
    if rng.random() < 0.5:
        font = _text_font(rng, max(7, cell // 5))
        for i in range(8):
            fx, fy = ox + i * cell + cell - cell // 4, oy + 8 * cell - cell // 4 - 2
            col = dark if (7 + i) % 2 == 0 else light
            d.text((fx, fy), 'abcdefgh'[i], font=font, fill=col)
            rx, ry = ox + 2, oy + i * cell + 1
            col = light if i % 2 == 1 else dark
            d.text((rx, ry), '87654321'[i], font=font, fill=col)
    lo = hi = warps = None
    shadow = False
    if EXTRA:
        sizes = _type_sizes(_piece_px(cell, rng), cell, rng)
        if rng.random() < 0.25:
            lo, hi = rng.uniform(0, 115), rng.uniform(175, 255)
        shadow = rng.random() < 0.15
        warps = _board_warps(rng)
    else:
        sizes = dict.fromkeys('KQRBNP', _piece_px(cell, rng))
    for r in range(8):
        for c in range(8):
            code = board[r][c]
            if code == '.':
                continue
            px = sizes[code.upper()]
            p = piece_image(set_name, code, 128)
            if warps:
                p = _warp(p, warps[code.upper()])
            p = p.resize((px, px), Image.LANCZOS)
            if lo is not None or shadow:
                p = _restyle(p, lo, hi, shadow)
            x = ox + c * cell + (cell - px) // 2
            y = oy + r * cell + (cell - px) // 2
            img.paste(p, (x, y), p)
    return img, (ox, oy, cell)


def _render_book(board, set_name, rng, cell, margin, hatch, extras):
    """Ink on paper. Rendered as grey levels (0 ink, 255 paper), then inked
    in the paper and ink colours."""
    size = cell * 8
    extras = rng.random() < 0.6 if extras is None else extras
    labels = extras and rng.random() < 0.7
    frame = rng.random() < 0.8 or labels
    fw = max(1, int(round(cell * rng.uniform(0.02, 0.09)))) if frame else 0
    lab_gap = int(cell * rng.uniform(0.15, 0.5))
    lab_size = cell * rng.uniform(0.25, 0.45)
    pad = margin + fw + 2
    if labels:
        pad = max(pad, fw + lab_gap + int(lab_size * 1.6) + 2)
    top_pad = bot_pad = pad
    if extras and rng.random() < 0.6:
        top_pad += int(cell * rng.uniform(0.5, 1.2))
    if extras and rng.random() < 0.6:
        bot_pad += int(cell * rng.uniform(0.5, 1.5))
    W, H = size + 2 * pad, size + top_pad + bot_pad
    ox, oy = pad, top_pad
    canvas = Image.new('L', (W, H), 255)
    d = ImageDraw.Draw(canvas)

    textured = (rng.random() < 0.85) if hatch is None else hatch
    if textured:
        pat, kind = _dark_pattern(size, size, cell, rng)
        if kind == 'grey' and hatch:
            pat, kind = _dark_pattern(size, size, cell, random.Random(rng.random()))
    else:
        pat = np.full((size, size), rng.randint(150, 215), np.uint8)
    dark_mask = np.zeros((size, size), bool)
    for r in range(8):
        for c in range(8):
            if (r + c) % 2 == 1:
                dark_mask[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = True
    # Pieces on near-black squares are printed with a white rim, or they
    # would vanish.
    force_halo = float(pat.mean()) < 110
    sq = np.where(dark_mask, pat, 255).astype(np.uint8)
    canvas.paste(Image.fromarray(sq, 'L'), (ox, oy))

    if frame:
        d.rectangle([ox - fw, oy - fw, ox + size + fw - 1, oy + size + fw - 1],
                    outline=0, width=fw)
        if rng.random() < 0.15:
            g = fw + max(2, cell // 12)
            d.rectangle([ox - g - 1, oy - g - 1, ox + size + g, oy + size + g],
                        outline=0, width=1)
    if labels:
        font = _text_font(rng, lab_size)
        both = rng.random() < 0.4
        for i in range(8):
            f = 'abcdefgh'[i]
            cx = ox + i * cell + cell / 2
            yb = oy + size + fw + lab_gap
            d.text((cx, yb), f, font=font, fill=0, anchor='mt')
            if both:
                d.text((cx, oy - fw - lab_gap), f, font=font, fill=0, anchor='mb')
            n = '87654321'[i]
            cy = oy + i * cell + cell / 2
            d.text((ox - fw - lab_gap, cy), n, font=font, fill=0, anchor='rm')
            if both:
                d.text((ox + size + fw + lab_gap, cy), n, font=font, fill=0,
                       anchor='lm')
    if extras:
        font = _text_font(rng, cell * rng.uniform(0.3, 0.6))
        if top_pad > pad:
            d.text((W / 2 + rng.uniform(-cell, cell), (top_pad - pad) / 2 + 1),
                   _caption(rng, rng.randint(1, 4)), font=font, fill=0,
                   anchor='mm')
        if bot_pad > pad:
            d.text((rng.uniform(0, cell), H - (bot_pad - pad) / 2 - 1),
                   _caption(rng, rng.randint(2, 8)), font=font, fill=0,
                   anchor='lm')

    px = _piece_px(cell, rng, rng.uniform(0.78, 1.0))
    if EXTRA:
        sizes = _type_sizes(px, cell, rng)
        halo = force_halo or rng.random() < 0.3
        # Line art as a rule; a grey-printed or photographed diagram keeps
        # the pieces' grey levels.
        thr = rng.uniform(_INK_MIN.get(set_name, 110), 200) \
            if rng.random() < 0.82 and set_name not in _NO_INK else None
        bold = rng.choice([0, 0, 0, 3, 3, 5])
        warps = _board_warps(rng)
    else:
        sizes = dict.fromkeys('KQRBNP', px)
        halo = rng.random() < 0.3
        thr = rng.uniform(110, 200)
        bold = rng.choice([0, 0, 0, 3, 5])
        warps = None
    for r in range(8):
        for c in range(8):
            code = board[r][c]
            if code == '.':
                continue
            px = sizes[code.upper()]
            ink, alpha = _book_piece(set_name, code, px, thr, bold,
                                     warps and warps[code.upper()])
            x = ox + c * cell + (cell - px) // 2 + rng.randint(-1, 1)
            y = oy + r * cell + (cell - px) // 2 + rng.randint(-1, 1)
            if halo and (r + c) % 2 == 1:
                # Hatching stopped short of the piece: a white rim.
                rim = alpha.filter(ImageFilter.MaxFilter(3 if px < 40 else 5))
                canvas.paste(255, (x, y), rim)
            canvas.paste(ink, (x, y), alpha)

    # Ink and paper colours.
    g = np.asarray(canvas).astype(np.float32) / 255
    paper = np.array(rng.choice([(255, 255, 255)] * 3 + [
        (rng.randint(235, 255), rng.randint(225, 245), rng.randint(190, 230)),
        (rng.randint(220, 245), rng.randint(215, 240), rng.randint(200, 230)),
        (rng.randint(240, 255), rng.randint(200, 225), rng.randint(150, 190)),
    ]), np.float32)
    inkc = np.array([rng.randint(0, 50)] * 3, np.float32)
    rgb = inkc + (paper - inkc) * g[..., None]
    return Image.fromarray(rgb.astype(np.uint8), 'RGB'), (ox, oy, cell)


# Sets whose black pieces are mostly mid-grey: a low ink threshold turns them
# white (rhosgfx), or no threshold separates black from white (firi, whose
# black pieces are light with a dark half). Checked by ink coverage per
# colour; see the README.
_INK_MIN = {'rhosgfx': 150}
_NO_INK = {'firi'}


def _warp(p, w):
    """A piece image under the board's shape warp (sx, sy, shear, angle).
    Fonts differ in proportions; this keeps the network from learning one
    set's."""
    sx, sy, sh, ang = w
    n = p.width
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    # Output -> input map about the centre: inverse of scale, shear, rotate.
    m = np.array([[ca, -sa], [sa, ca]]) @ np.array([[1, sh], [0, 1]]) @ \
        np.diag([sx, sy])
    inv = np.linalg.inv(m)
    c = n / 2
    off = np.array([c, c]) - inv @ np.array([c, c])
    return p.transform((n, n), Image.AFFINE,
                       (inv[0, 0], inv[0, 1], off[0], inv[1, 0], inv[1, 1],
                        off[1]), Image.BICUBIC)


def _board_warps(rng):
    """Per piece type warp for one board, or None (most boards)."""
    if rng.random() < 0.55:
        return None
    return {t: (rng.uniform(0.85, 1.12), rng.uniform(0.85, 1.12),
                rng.uniform(-0.12, 0.12), rng.uniform(-4, 4)) for t in 'KQRBNP'}


def _book_piece(set_name, code, px, thr, bold, warp=None):
    """A piece inked at 128 px (so thin outlines survive the threshold),
    optionally with its strokes thickened, then scaled to `px`."""
    key = ('ink', set_name, code, None if thr is None else int(thr) // 20 * 20, bold)
    if key not in _piece_cache:
        p = piece_image(set_name, code, 128)
        if thr is None:
            arr = np.asarray(p).astype(np.float32)
            lum = arr[..., :3] @ np.array([0.299, 0.587, 0.114])
            ink = Image.fromarray(lum.astype(np.uint8), 'L')
            alpha = p.getchannel('A')
        else:
            ink, alpha = _ink_piece(p, None, thr)
        if bold:
            bink = ink.filter(ImageFilter.MinFilter(bold))
            balpha = alpha.filter(ImageFilter.MaxFilter(bold))
            # Never so bold that a white piece fills in and reads as black.
            a = np.asarray(balpha) / 255
            cover = ((1 - np.asarray(bink) / 255) * a).sum() / max(a.sum(), 1)
            if code.islower() or cover < 0.6 or not EXTRA:
                ink, alpha = bink, balpha
        _piece_cache[key] = (ink, alpha)
    ink, alpha = _piece_cache[key]
    if warp is not None:
        ink = _warp(Image.merge('LA', (ink, alpha)), warp)
        ink, alpha = ink.getchannel('L'), ink.getchannel('A')
    return ink.resize((px, px), Image.LANCZOS), alpha.resize((px, px), Image.LANCZOS)


def capture(img, rect, rng, style, lowres=False):
    """What taking the picture does: returns (image, (x0, y0, cw, ch)) with
    the lattice the detector would fit (axis-aligned, mean of the moved
    corners; cells are cw x ch, not always square).

    `lowres`: the board was rendered small and is upscaled here, as when a
    small diagram is zoomed in a PDF viewer or a phone screenshot is scaled.
    """
    ox, oy, cell = rect
    W, H = img.size
    book = style == 'book'
    # Ink spread or thinning, at the rendered resolution.
    if book and rng.random() < 0.3:
        f = ImageFilter.MinFilter(3) if rng.random() < 0.65 else ImageFilter.MaxFilter(3)
        img = img.filter(f)
    # Halftone / dithered print or fax: 1-bit, then smoothed by the scan.
    if book and rng.random() < 0.08:
        s = rng.uniform(1.0, 2.0)
        small = img.convert('L').resize((max(8, int(W * s)), max(8, int(H * s))),
                                        Image.BILINEAR)
        img = small.convert('1').convert('L').resize((W, H), Image.BOX).convert('RGB')
    # Geometry: slight rotation and perspective about the board centre.
    corners = np.array([[ox, oy], [ox + 8 * cell, oy], [ox + 8 * cell, oy + 8 * cell],
                        [ox, oy + 8 * cell]], np.float64)
    if rng.random() < (0.35 if book else 0.2):
        ang = math.radians(rng.uniform(-2, 2))
        persp = rng.random() < 0.5
        bs = 8 * cell
        src = corners.copy()
        c0 = corners.mean(0)
        rot = np.array([[math.cos(ang), -math.sin(ang)],
                        [math.sin(ang), math.cos(ang)]])
        dst = (corners - c0) @ rot.T + c0
        if persp:
            dst += np.array([[rng.uniform(-1, 1), rng.uniform(-1, 1)]
                             for _ in range(4)]) * bs * 0.02
        # PIL maps output -> input: solve the homography dst -> src.
        coeffs = _homography(dst, src)
        fill = tuple(int(v) for v in np.asarray(img)[0, 0][:3]) \
            if np.asarray(img).ndim == 3 else 255
        img = img.transform((W, H), Image.PERSPECTIVE, coeffs, Image.BICUBIC,
                            fillcolor=fill)
        corners = dst
    # A stretched picture (a camera app or a screen scaling one axis): the
    # squares are no longer square.
    if rng.random() < 0.08:
        sx = rng.uniform(0.72, 1.4)
        img = img.resize((max(16, int(W * sx)), H), Image.BICUBIC)
        corners = corners * np.array([img.size[0] / W, 1.0])
        W, H = img.size
    # Upscale a small rendering.
    if lowres:
        s = rng.uniform(1.5, 4.0)
        img = img.resize((int(W * s), int(H * s)),
                         rng.choice([Image.BILINEAR, Image.BICUBIC, Image.NEAREST,
                                     Image.LANCZOS]))
        corners = corners * np.array([img.size[0] / W, img.size[1] / H])
        W, H = img.size
    elif rng.random() < 0.15:
        # Or a big one shrunk (a thumbnail), with its aliasing.
        s = rng.uniform(0.45, 0.8)
        nw, nh = max(64, int(W * s)), max(64, int(H * s))
        img = img.resize((nw, nh), rng.choice([Image.BILINEAR, Image.NEAREST,
                                               Image.BOX]))
        corners = corners * np.array([nw / W, nh / H])
        W, H = img.size
    img = degrade(img, rng, book=book)
    left = (corners[0, 0] + corners[3, 0]) / 2
    right = (corners[1, 0] + corners[2, 0]) / 2
    top = (corners[0, 1] + corners[1, 1]) / 2
    bottom = (corners[2, 1] + corners[3, 1]) / 2
    return img, (left, top, (right - left) / 8, (bottom - top) / 8)


def _homography(src, dst):
    """Coefficients (a..h) with dst = H(src), for Image.transform PERSPECTIVE
    (which maps output pixel coordinates to input ones)."""
    A, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.linalg.solve(np.array(A, np.float64), np.array(b, np.float64)).tolist()


def degrade(img, rng, book=False):
    """Board-level capture artefacts: light, paper, blur, noise, JPEG, tone."""
    arr = np.asarray(img.convert('RGB')).astype(np.float32)
    H, W = arr.shape[:2]
    if rng.random() < (0.35 if book else 0.15):
        # Uneven light: a gradient and a vignette.
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        gx, gy = rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25)
        field = 1 + gx * (xx / W - 0.5) + gy * (yy / H - 0.5)
        if rng.random() < 0.5:
            r2 = ((xx / W - 0.5) ** 2 + (yy / H - 0.5) ** 2) * 2
            field *= 1 - rng.uniform(0, 0.3) * r2
        arr *= field[..., None]
    if book and rng.random() < 0.3:
        # Paper grain: low-frequency blotches plus fine fibre noise.
        nr = _nrng(rng)
        k = rng.choice([6, 12, 24])
        low = nr.normal(0, 1, (k, k)).astype(np.float32)
        low = np.asarray(Image.fromarray(low, 'F').resize((W, H), Image.BICUBIC))
        arr += low[..., None] * rng.uniform(3, 12)
        arr += nr.normal(0, rng.uniform(2, 8), (H, W, 1))
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    if rng.random() < 0.5:
        img = img.filter(ImageFilter.GaussianBlur(rng.uniform(0.2, 1.5)))
    arr = np.asarray(img).astype(np.float32)
    if rng.random() < 0.7:
        c = rng.uniform(0.65, 1.25)
        b = rng.uniform(-35, 35)
        arr = (arr - 128) * c + 128 + b
    if rng.random() < 0.3:
        gamma = rng.uniform(0.7, 1.5)
        arr = 255 * (np.clip(arr, 0, 255) / 255) ** gamma
    if rng.random() < 0.5:
        arr = arr + _nrng(rng).normal(0, rng.uniform(2, 12), arr.shape)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    if rng.random() < 0.55:
        buf = io.BytesIO()
        q = rng.randint(8, 40) if rng.random() < 0.35 else rng.randint(40, 92)
        img.save(buf, 'JPEG', quality=q)
        img = Image.open(io.BytesIO(buf.getvalue())).convert('RGB')
    return img


def grayscale(img):
    arr = np.asarray(img.convert('RGB')).astype(np.int64)
    return ((299 * arr[..., 0] + 587 * arr[..., 1] + 114 * arr[..., 2]) // 1000
            ).astype(np.float64)


def cell_to_input(gray, x0, y0, w, h):
    """Area-average [x0, x0+w) x [y0, y0+h) of `gray` to 32x32 in [0, 1].

    Must match `cellInput` in lib/vision/board_recognizer.dart exactly.
    """
    H, W = gray.shape
    ii = np.zeros((H + 1, W + 1))
    ii[1:, 1:] = gray.cumsum(0).cumsum(1)
    return _cell_from_integral(ii, W, H, x0, y0, w, h)


def _bounds(start, extent, n, limit):
    out = []
    for k in range(n):
        a = int(math.floor(start + k * extent / n))
        b = int(math.floor(start + (k + 1) * extent / n))
        a = min(max(a, 0), limit - 1)
        b = min(max(b, a + 1), limit)
        out.append((a, b))
    return out


def _cell_from_integral(ii, W, H, x0, y0, w, h):
    xs = _bounds(x0, w, INPUT, W)
    ys = _bounds(y0, h, INPUT, H)
    xa = np.array([a for a, _ in xs]); xb = np.array([b for _, b in xs])
    ya = np.array([a for a, _ in ys]); yb = np.array([b for _, b in ys])
    s = (ii[yb][:, xb] - ii[ya][:, xb] - ii[yb][:, xa] + ii[ya][:, xa])
    area = (yb - ya)[:, None] * (xb - xa)[None, :]
    return (s / area / 255.0).astype(np.float32)


def sample_board(rng, sets, look=None):
    """Render and capture one random board.

    Returns (image, placement, (x0, y0, cw, ch), set_name, look)."""
    board = random_placement(rng)
    set_name = rng.choice(sets)
    look = look or ('book' if rng.random() < 0.45 else 'screen')
    lowres = rng.random() < 0.3
    cell = rng.randint(12, 26) if lowres else rng.randint(22, 90)
    margin = rng.randint(0, 12)
    img, rect = render_board(board, set_name, rng, cell=cell, style=look,
                             margin=margin)
    img, rect = capture(img, rect, rng, look, lowres=lowres)
    return img, board, rect, set_name, look


def board_samples(rng, sets, jitter=True):
    """Render one random board; return (inputs [64,32,32], labels [64], set)."""
    img, board, (ox, oy, cw, ch), set_name, _ = sample_board(rng, sets)
    gray = grayscale(img)
    H, W = gray.shape
    ii = np.zeros((H + 1, W + 1))
    ii[1:, 1:] = gray.cumsum(0).cumsum(1)
    # A lattice error shared by the whole board (imperfect detection) plus a
    # small per-cell wobble.
    k = 1 + (rng.uniform(-0.04, 0.04) if jitter else 0)
    gw, gh = cw * k, ch * k
    gx = ox + (rng.uniform(-0.08, 0.08) * cw if jitter else 0)
    gy = oy + (rng.uniform(-0.08, 0.08) * ch if jitter else 0)
    xs, ys = [], []
    for r in range(8):
        for c in range(8):
            dx = rng.uniform(-0.05, 0.05) * cw if jitter else 0
            dy = rng.uniform(-0.05, 0.05) * ch if jitter else 0
            sc = rng.uniform(0.94, 1.06) if jitter else 1
            w, h = gw * sc, gh * sc
            x0 = gx + c * gw + dx - (w - gw) / 2
            y0 = gy + r * gh + dy - (h - gh) / 2
            xs.append(_cell_from_integral(ii, W, H, x0, y0, w, h))
            ys.append(CLASSES.index(board[r][c]))
    return np.stack(xs), np.array(ys, np.int64), set_name
