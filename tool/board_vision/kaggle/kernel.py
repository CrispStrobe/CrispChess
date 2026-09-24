"""Kaggle kernel: generate board-square data and train the classifier on GPU.

Everything it needs comes from the private dataset built by
build_dataset.sh (src.tar.gz): the generator and trainer, pre-rendered piece
PNGs, permissive fonts and the v1 benchmark. Nothing is fetched except, on a
P100 whose preinstalled torch lacks sm_60 kernels, a cu118 torch wheel.

Outputs in /kaggle/working: model.pt (state dict), board_squares.onnx,
gen.log, train.log, progress.txt.

The defaults are the shipped model's recipe (60k boards, 18 epochs, batch
512). Environment overrides for experiments: BV_SHARDS, BV_BOARDS,
BV_EPOCHS, BV_BATCH, BV_LR, BV_AUGMENT=1, BV_EXTRA_AUG=1 (render.py). A
script kernel gets no environment from the push, so set them at the top of
this file for a run.
"""

import glob
import os
import subprocess
import sys
import tarfile
import time

SHARDS = int(os.environ.get('BV_SHARDS', 24))
BOARDS = int(os.environ.get('BV_BOARDS', 2500))  # per shard
EPOCHS = int(os.environ.get('BV_EPOCHS', 18))
BATCH = os.environ.get('BV_BATCH', '512')
LR = os.environ.get('BV_LR', '3e-3')
# Train-time jitter (train.py --augment): tried, not better; off.
AUGMENT = ['--augment'] if os.environ.get('BV_AUGMENT') == '1' else []
SEED = 11

W = os.environ.get('BV_WORK', '/kaggle/working')
T = os.environ.get('BV_TMP', '/kaggle/tmp')
INPUT = os.environ.get('BV_INPUT', '/kaggle/input')
os.makedirs(T, exist_ok=True)
t0 = time.time()


def progress(msg):
    line = f'[{(time.time() - t0) / 60:6.1f} min] {msg}'
    print(line, flush=True)
    with open(os.path.join(W, 'progress.txt'), 'a') as f:
        f.write(line + '\n')


def run(cmd, log, env=None):
    progress('run ' + ' '.join(cmd))
    with open(os.path.join(W, log), 'a') as f:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             env=env, text=True)
        for line in p.stdout:
            f.write(line)
            f.flush()
            print(line, end='', flush=True)
        rc = p.wait()
    progress(f'exit {rc}')
    if rc:
        raise SystemExit(rc)


# Kaggle unpacks archives in datasets, so the tree may already be there.
found = glob.glob(os.path.join(INPUT, '**', 'board_vision', 'render.py'),
                  recursive=True)
if found:
    S = os.path.dirname(os.path.dirname(found[0]))
else:
    src_tar = glob.glob(os.path.join(INPUT, '**', 'src.tar.gz'), recursive=True)
    if not src_tar:
        raise SystemExit(f'neither src/ nor src.tar.gz under {INPUT}')
    with tarfile.open(src_tar[0]) as tf:
        tf.extractall(T)
    S = os.path.join(T, 'src')
import hashlib  # noqa: E402
progress(f'sources in {S}; render.py md5 ' + hashlib.md5(open(
    os.path.join(S, 'board_vision', 'render.py'), 'rb').read()).hexdigest())


def has_nvidia():
    try:
        return subprocess.run(['nvidia-smi', '--query-gpu=name,compute_cap',
                               '--format=csv']).returncode == 0
    except FileNotFoundError:
        return False


nvidia = has_nvidia()

probe = ('import torch; x = torch.randn(8, 1, 32, 32, device="cuda"); '
         'print(torch.nn.Conv2d(1, 4, 3).cuda()(x).sum().item())')
gpu = subprocess.run([sys.executable, '-c', probe]).returncode == 0
if not gpu and nvidia:
    progress('preinstalled torch cannot run on this GPU; installing cu118 torch')
    subprocess.run([sys.executable, '-m', 'pip', 'install', '-q',
                    'torch==2.5.1', '--index-url',
                    'https://download.pytorch.org/whl/cu118'], check=False)
    gpu = subprocess.run([sys.executable, '-c', probe]).returncode == 0
progress(f'gpu usable: {gpu}')

env = dict(os.environ, BV_PIECE_PNG=os.path.join(S, 'pieces_png'),
           BV_DEJAVU_DIR=os.path.join(S, 'dejavu'), PYTHONUNBUFFERED='1')
bv = os.path.join(S, 'board_vision')
procs = str(max(1, os.cpu_count() or 4))

run([sys.executable, os.path.join(bv, 'bench.py'), '--out',
     os.path.join(T, 'bench_v2'), '--per-style', os.environ.get('BV_BENCH_PER_STYLE', '16'), '--seed', '2027'],
    'gen.log', env)
run([sys.executable, os.path.join(bv, 'gen.py'), '--out', os.path.join(T, 'data'),
     '--boards', str(BOARDS), '--shards', str(SHARDS), '--procs', procs,
     '--seed', str(SEED)], 'gen.log', env)

benches = [os.path.join(T, 'bench_v2')]
if os.path.isdir(os.path.join(S, 'bench_v1')):
    benches.insert(0, os.path.join(S, 'bench_v1'))
run([sys.executable, os.path.join(bv, 'train.py'), '--data',
     os.path.join(T, 'data'), '--arch', 'v2',
     '--epochs', str(EPOCHS if gpu else 4), '--batch', BATCH, '--lr', LR,
     '--threads', procs, *AUGMENT, '--save', os.path.join(W, 'model.pt'),
     '--export', os.path.join(W, 'board_squares.onnx'), '--bench', *benches],
    'train.log', env)
progress('done')
