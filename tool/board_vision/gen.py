"""Generate cached training shards of 32x32 square crops.

    python3 tool/board_vision/gen.py --out /tmp/bv_data --boards 4000 --shards 3

Each shard is an .npz with x (uint8 [N,32,32]), y (int64 [N]), s (set index
[N]) and names (the set names s indexes, so a shard stays readable after the
set list changes). Runs up to --procs processes, one shard each; each stays
~150 MB. With BV_PIECE_PNG set (see prerender.py) it needs no cairosvg.
"""

import argparse
import multiprocessing as mp
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import render as R  # noqa: E402

ALL_SETS = R.SVG_SETS + list(R.FONT_SETS)


def _shard(args):
    out, idx, boards, seed = args
    rng = random.Random(seed)
    xs, ys, ss = [], [], []
    for _ in range(boards):
        x, y, set_name = R.board_samples(rng, ALL_SETS)
        xs.append(np.round(x * 255).astype(np.uint8))
        ys.append(y)
        ss.append(np.full(len(y), ALL_SETS.index(set_name), np.int8))
    path = os.path.join(out, f'shard_{idx:02d}.npz')
    np.savez_compressed(path, x=np.concatenate(xs), y=np.concatenate(ys),
                        s=np.concatenate(ss), names=np.array(ALL_SETS))
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--boards', type=int, default=4000, help='boards per shard')
    ap.add_argument('--shards', type=int, default=3)
    ap.add_argument('--seed', type=int, default=0)
    ap.add_argument('--procs', type=int, default=3,
                    help='worker processes (~150 MB each)')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    jobs = [(a.out, i, a.boards, a.seed * 1000 + i) for i in range(a.shards)]
    with mp.Pool(min(a.shards, a.procs)) as pool:
        for p in pool.imap_unordered(_shard, jobs):
            print('wrote', p, flush=True)


if __name__ == '__main__':
    main()
