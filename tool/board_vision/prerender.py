"""Pre-render the SVG piece sets to PNG, for machines without cairosvg.

    python3 tool/board_vision/prerender.py --out /tmp/bv_pieces
    BV_PIECE_PNG=/tmp/bv_pieces python3 tool/board_vision/gen.py ...

Writes <out>/<set>/<w|b><K..P>.png at the 128 px the renderer draws pieces
at, so boards rendered from them are identical to ones rendered from the SVGs.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import render as R  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    for s in R.SVG_SETS:
        os.makedirs(os.path.join(a.out, s), exist_ok=True)
        for code in 'KQRBNPkqrbnp':
            color = 'w' if code.isupper() else 'b'
            R._svg_piece(s, code, 128).save(
                os.path.join(a.out, s, f'{color}{code.upper()}.png'))
    print('wrote', len(R.SVG_SETS) * 12, 'pieces to', a.out)


if __name__ == '__main__':
    main()
