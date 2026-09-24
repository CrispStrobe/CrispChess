"""Train the square classifier and export it to ONNX.

    # generalisation experiment: never train on papercut, report it separately
    python3 tool/board_vision/train.py --data /tmp/bv_data --holdout papercut \
        --bench /tmp/bv_bench
    # shipped model, trained on every source
    python3 tool/board_vision/train.py --data /tmp/bv_data --bench /tmp/bv_bench \
        --epochs 20 --batch 1024 --lr 4e-3 --export assets/models/board_squares.onnx
    # re-export (or re-score) saved weights
    python3 tool/board_vision/train.py --init model.pt --epochs 0 \
        --bench /tmp/bv_bench --export assets/models/board_squares.onnx

On a CPU (two threads by default) the squares are memory-mapped from disk
and indexed in place, never copied; on a GPU they are moved to it whole as
uint8. The export uses Conv/Relu/MaxPool/Flatten/Gemm only — all implemented
by package:onnx_runtime_dart's interpreter — with a dynamic batch axis.
"""

import argparse
import csv
import glob
import os
import sys

import numpy as np
import torch
import torch.nn as nn

sys.path.insert(0, os.path.dirname(__file__))
import render as R  # noqa: E402
from PIL import Image  # noqa: E402


class SquareNet(nn.Module):
    """'v1': the first shipped model (16/32/48 channels, ~70k parameters).
    'v2': wider, with a second convolution at 8x8 (~210k parameters, ~3x the
    compute) — the capacity the print-realism data needs."""

    def __init__(self, arch='v2'):
        super().__init__()
        def conv(i, o):
            return [nn.Conv2d(i, o, 3, padding=1), nn.BatchNorm2d(o), nn.ReLU()]
        pool = nn.MaxPool2d(2)
        if arch == 'v1':
            layers = [*conv(1, 16), pool, *conv(16, 32), nn.MaxPool2d(2),
                      *conv(32, 48), nn.MaxPool2d(2)]
            flat, hidden = 48 * 4 * 4, 64
        elif arch == 'v2':
            layers = [*conv(1, 24), pool, *conv(24, 48), nn.MaxPool2d(2),
                      *conv(48, 64), *conv(64, 64), nn.MaxPool2d(2)]
            flat, hidden = 64 * 4 * 4, 128
        else:
            raise ValueError(arch)
        self.features = nn.Sequential(*layers)
        self.head = nn.Sequential(nn.Flatten(), nn.Dropout(0.2),
                                  nn.Linear(flat, hidden), nn.ReLU(),
                                  nn.Linear(hidden, len(R.CLASSES)))

    def forward(self, x):
        return self.head(self.features(x))


def fuse_bn(model):
    """Fold every BatchNorm into the conv before it (inference graph)."""
    layers = list(model.features)
    out = []
    for m in layers:
        if isinstance(m, nn.BatchNorm2d) and isinstance(out[-1], nn.Conv2d):
            conv = out[-1]
            std = torch.sqrt(m.running_var + m.eps)
            w = conv.weight * (m.weight / std).reshape(-1, 1, 1, 1)
            b = (conv.bias - m.running_mean) * m.weight / std + m.bias
            fused = nn.Conv2d(conv.in_channels, conv.out_channels, 3, padding=1)
            fused = fused.to(conv.weight.device)
            fused.weight.data, fused.bias.data = w.detach(), b.detach()
            out[-1] = fused
        else:
            out.append(m)
    model.features = nn.Sequential(*out)
    return model


def load(data):
    """Shards merged into one on-disk array, memory-mapped.

    12k boards are ~790 MB of uint8 squares; mapped from disk they live in the
    page cache, which the kernel can reclaim, instead of the process's RSS.
    Labels and set ids are small and stay in RAM.
    """
    paths = sorted(glob.glob(os.path.join(data, 'shard_*.npz')))
    merged = os.path.join(data, f'merged_{len(paths)}.npy')
    ys, ss, names = [], [], None
    for p in paths:
        z = np.load(p)
        ys.append(z['y']); ss.append(z['s'])
        shard_names = list(z['names'])
        if names is not None and shard_names != names:
            raise SystemExit(f'{p}: set list differs from the other shards')
        names = shard_names
    y, s = np.concatenate(ys), np.concatenate(ss)
    if not os.path.exists(merged):
        x = np.lib.format.open_memmap(merged + '.tmp', mode='w+', dtype=np.uint8,
                                      shape=(len(y), R.INPUT, R.INPUT))
        at = 0
        for p in paths:
            part = np.load(p)['x']
            x[at:at + len(part)] = part
            at += len(part)
            del part
        x.flush()
        del x
        os.rename(merged + '.tmp', merged)
    return np.load(merged, mmap_mode='r'), y, s, names


def _batch(x, idx, dev):
    """Samples `idx` as a float batch on `dev` (x is a numpy memmap or a
    uint8 tensor already on the device)."""
    if isinstance(x, torch.Tensor):
        return x[torch.as_tensor(idx, device=x.device)].float().unsqueeze(1) / 255
    return torch.from_numpy(x[idx]).to(dev).float().unsqueeze(1) / 255


def evaluate(model, x, y, idx, dev='cpu', bs=1024):
    """Accuracy over the samples at `idx` (indices, never a copied subset)."""
    model.eval()
    correct = 0
    with torch.no_grad():
        for i in range(0, len(idx), bs):
            j = idx[i:i + bs]
            pred = model(_batch(x, j, dev)).argmax(1).cpu().numpy()
            correct += (pred == y[j]).sum()
    return correct / max(1, len(idx))


def bench(model, bench_dir, dev='cpu'):
    """Per-style square and whole-board accuracy on bench.py boards, using
    each board's true rect (classification only, no detection)."""
    model.eval()
    stats = {}
    with open(os.path.join(bench_dir, 'labels.tsv')) as f:
        rows = list(csv.DictReader(f, delimiter='\t'))
    for row in rows:
        gray = R.grayscale(Image.open(os.path.join(bench_dir, row['file'])))
        left, top, size = (float(row[k]) for k in ('left', 'top', 'size'))
        cw = size / 8
        ch = float(row.get('height') or size) / 8
        xb = np.stack([R.cell_to_input(gray, left + c * cw, top + r * ch,
                                       cw, ch)
                       for r in range(8) for c in range(8)])
        with torch.no_grad():
            pred = model(torch.from_numpy(xb).unsqueeze(1).to(dev)
                         ).argmax(1).cpu().numpy()
        want = [R.CLASSES.index(ch)
                for row8 in R.fen_to_placement(row['placement']) for ch in row8]
        ok = int((pred == np.array(want)).sum())
        key = row['style'] + ('/' + row['look'] if 'look' in row else '')
        st = stats.setdefault(key, [0, 0, 0])
        st[0] += ok; st[1] += 1; st[2] += ok == 64
    return stats


def augment(xb):
    """Per-sample jitter on the device: the crop shifted up to 1.5 px and
    scaled ±8 % (detection error beyond what the shards hold), and tone
    stretched and offset a little."""
    n = len(xb)
    dev = xb.device
    s = 1 + (torch.rand(n, device=dev) - 0.5) * 0.16
    t = (torch.rand(n, 2, device=dev) - 0.5) * (3 / 16)  # ±1.5 px of 32
    theta = torch.zeros(n, 2, 3, device=dev)
    theta[:, 0, 0] = s
    theta[:, 1, 1] = s
    theta[:, :, 2] = t
    grid = torch.nn.functional.affine_grid(theta, xb.shape, align_corners=False)
    out = torch.nn.functional.grid_sample(xb, grid, padding_mode='border',
                                          align_corners=False)
    c = 1 + (torch.rand(n, 1, 1, 1, device=dev) - 0.5) * 0.4
    b = (torch.rand(n, 1, 1, 1, device=dev) - 0.5) * 0.2
    out = ((out - 0.5) * c + 0.5 + b).clamp(0, 1)
    keep = torch.rand(n, device=dev) < 0.3
    out[keep] = xb[keep]
    return out


def export(model, path):
    model = fuse_bn(model.cpu().eval())
    dummy = torch.zeros(64, 1, 32, 32)
    kw = dict(input_names=['input'], output_names=['logits'], opset_version=13,
              dynamic_axes={'input': {0: 'n'}, 'logits': {0: 'n'}})
    try:
        torch.onnx.export(model, dummy, path, dynamo=False, **kw)
    except TypeError:  # torch without the dynamo switch: legacy exporter
        torch.onnx.export(model, dummy, path, **kw)
    try:
        import onnx
    except ImportError:
        print('exported', path, os.path.getsize(path), 'bytes (onnx not '
              'installed, graph not checked)')
        return
    m = onnx.load(path)
    onnx.checker.check_model(m)
    print('exported', path, os.path.getsize(path), 'bytes; ops',
          sorted({n.op_type for n in m.graph.node}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', help='gen.py shards (omit with --epochs 0)')
    ap.add_argument('--holdout', nargs='*', default=[],
                    help='sets never trained on, reported separately')
    ap.add_argument('--exclude', nargs='*', default=[],
                    help='sets dropped from the data entirely')
    ap.add_argument('--bench', nargs='*', default=[],
                    help='bench.py outputs to score on at the end')
    ap.add_argument('--arch', default='v2', choices=['v1', 'v2'])
    ap.add_argument('--epochs', type=int, default=8)
    ap.add_argument('--batch', type=int, default=256)
    ap.add_argument('--lr', type=float, default=3e-3)
    ap.add_argument('--threads', type=int, default=2)
    ap.add_argument('--augment', action='store_true',
                    help='shift/scale/tone jitter per sample while training')
    ap.add_argument('--init', help='state dict to start from')
    ap.add_argument('--save', help='write the trained state dict here')
    ap.add_argument('--export')
    a = ap.parse_args()
    torch.set_num_threads(a.threads)
    torch.manual_seed(0)
    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    torch.backends.cudnn.benchmark = True

    model = SquareNet(a.arch).to(dev)
    if a.init:
        model.load_state_dict(torch.load(a.init, map_location=dev))

    if a.epochs > 0:
        x, y, s, names = load(a.data)
        for n in a.holdout + a.exclude:
            if n not in names:
                raise SystemExit(f'unknown set {n}; shards have {names}')
        held = np.isin(s, [names.index(h) for h in a.holdout])
        excluded = np.isin(s, [names.index(e) for e in a.exclude])
        rng = np.random.default_rng(0)
        # 5% of the seen sets for validation, the held-out sets entirely.
        val_seen = (~held) & (~excluded) & (rng.random(len(y)) < 0.05)
        train = np.flatnonzero((~held) & (~excluded) & (~val_seen))
        print(f'train {len(train)}  val-seen {val_seen.sum()}  '
              f'held-out {held.sum()}  device {dev}', flush=True)
        if dev == 'cuda':
            # The squares are uint8; a few million fit on any training GPU.
            x = torch.from_numpy(np.ascontiguousarray(x)).to(dev)
        yt = torch.from_numpy(y).to(dev)

        opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
        per_epoch = len(train) // a.batch
        steps = a.epochs * per_epoch
        sched = torch.optim.lr_scheduler.OneCycleLR(opt, a.lr, total_steps=steps)
        lossf = nn.CrossEntropyLoss(label_smoothing=0.05)
        for ep in range(a.epochs):
            model.train()
            perm = rng.permutation(train)
            tot = 0.0
            for k in range(per_epoch):
                # Sorted indices read the big array in order: much faster.
                idx = np.sort(perm[k * a.batch:(k + 1) * a.batch])
                xb = _batch(x, idx, dev)
                # Mirroring keeps every piece's identity (knights face both
                # ways across sets) and doubles the look of each style.
                flip = torch.rand(len(idx), device=dev) < 0.5
                xb[flip] = xb[flip].flip(-1)
                if a.augment:
                    xb = augment(xb)
                yb = yt[torch.as_tensor(idx, device=dev)]
                loss = lossf(model(xb), yb)
                opt.zero_grad(); loss.backward(); opt.step(); sched.step()
                tot += loss.item()
            acc = evaluate(model, x, y, np.flatnonzero(val_seen), dev)
            print(f'epoch {ep + 1}: loss {tot / per_epoch:.4f}  '
                  f'val-seen {acc:.4%}', flush=True)
            if a.save:
                torch.save(model.state_dict(), a.save)

        print('per-set accuracy:')
        for i, name in enumerate(names):
            if name in a.exclude:
                continue
            m = np.flatnonzero((s == i) & (val_seen | held))
            tag = 'HELD-OUT' if name in a.holdout else 'seen'
            print(f'  {name:20s} {tag:8s} {evaluate(model, x, y, m, dev):.4%} '
                  f'({len(m)} squares)')

    for b in a.bench:
        print(f'bench {b} (true board rect):')
        tot = [0, 0, 0]
        for style, (ok, boards, whole) in sorted(bench(model, b, dev).items()):
            tag = 'HELD-OUT' if style.split('/')[0] in a.holdout else ''
            print(f'  {style:26s} squares {ok / (64 * boards):.2%}  boards '
                  f'{whole}/{boards} {tag}')
            tot = [tot[0] + ok, tot[1] + boards, tot[2] + whole]
        print(f'  {"all":26s} squares {tot[0] / (64 * tot[1]):.2%}  boards '
              f'{tot[2]}/{tot[1]}', flush=True)

    if a.export:
        export(model, a.export)


if __name__ == '__main__':
    main()
