"""Kaggle kernel: train the photo-board square classifiers.

Two MobileNetV3-small classifiers for lib/vision/photo/:
  occupancy: 100x100 crop -> empty / occupied
  pieces:    100x200 crop (W x H) -> 12 piece classes
cut exactly as chesscog cuts them (crops.py, shipped in the private dataset
chr1s4/crispchess-board-photo-src together with real_labels.json).

Data, all permissively licensed, fetched at run time:
  * chesscog synthetic renders (Wolflein & Arandjelovic, OSF xf3ka, CC BY 4.0),
    streamed straight out of the split train zip (no 7 GB on disk);
  * samryan18/chess-dataset (MIT): 500 top-down photos, FEN in the filename;
  * Roboflow "chess pieces" via RF100 (CC BY 4.0): 289 angled photos with boxes.
Real images get their board corners and per-cell labels from real_labels.json
(tool/board_photo/py/make_real_labels.py).

Outputs (/kaggle/working): board_photo_occupancy.onnx, board_photo_pieces.onnx,
*.pt state dicts, metrics.json, progress.txt.

The shipped models are this recipe's run "board-photo-v2" (T4, 50 min).
Tried and not better: a from-scratch run without ImageNet weights
(BP_PRETRAINED=0), and "v3" with 3600 synthetic boards, 12 piece epochs and
much stronger colour/shape augmentation - both lost accuracy on every
held-out set, the unseen chesscog set included.

GPU if it is a T4-class device (sm >= 70; Kaggle's torch has no sm_60 kernels,
so a P100 draw trains on CPU with a smaller budget).
"""
import glob, io, json, os, random, struct, subprocess, sys, tarfile, time, zlib

VERSION = "board-photo-v2"
PRETRAINED = os.environ.get("BP_PRETRAINED", "1") == "1"
N_SYN = int(os.environ.get("BP_SYN", 2400))        # synthetic training images
N_SYN_VAL = int(os.environ.get("BP_SYN_VAL", 120))
# Overrides for a small local dry run (see README); on Kaggle all unset.
W = os.environ.get("BP_WORK", "/kaggle/working")
T = os.environ.get("BP_TMP", "/kaggle/tmp")
INPUT = os.environ.get("BP_INPUT", "/kaggle/input")
SCALE = float(os.environ.get("BP_SCALE", 1.0))  # training budget multiplier
REAL_LIMIT = int(os.environ.get("BP_REAL_LIMIT", 0))
os.makedirs(T, exist_ok=True)
t0 = time.time()


def progress(msg):
    line = f"[{(time.time() - t0) / 60:6.1f} min] {msg}"
    print(line, flush=True)
    with open(os.path.join(W, "progress.txt"), "a") as f:
        f.write(line + "\n")


progress(f"{VERSION} pretrained={PRETRAINED}")
import numpy as np
import cv2
import torch
import torchvision
from torch import nn

dev = "cpu"
if torch.cuda.is_available():
    cap = torch.cuda.get_device_capability()
    name = torch.cuda.get_device_name()
    progress(f"GPU {name} sm_{cap[0]}{cap[1]}")
    if cap[0] * 10 + cap[1] >= 70:
        dev = "cuda"
    else:
        progress("P100_LOTTERY: torch lacks sm_60 kernels here; training on CPU")
CPU = dev == "cpu"
torch.set_num_threads(os.cpu_count() or 4)
progress(f"device {dev}, cpus {os.cpu_count()}, torch {torch.__version__}")

src = [p for p in glob.glob(os.path.join(INPUT, "**", "real_labels.json"), recursive=True)]
assert src, "attach chr1s4/crispchess-board-photo-src"
SRC = os.path.dirname(src[0])
sys.path.insert(0, SRC)
import crops as C  # noqa: E402

LABELS = json.load(open(src[0]))["images"]
rng = random.Random(7)

# ---------------------------------------------------------------- downloads
import requests  # noqa: E402


def fetch(url, path):
    if os.path.exists(path):
        return path
    with open_stream(url) as r:
        with open(path + ".part", "wb") as f:
            for b in r.iter_content(1 << 20):
                f.write(b)
    os.replace(path + ".part", path)
    return path


def open_stream(url, tries=8):
    """GET with retries: OSF answers bursts with 429."""
    for k in range(tries):
        r = requests.get(url, stream=True, timeout=300)
        if r.status_code == 200:
            return r
        progress(f"GET {url}: HTTP {r.status_code}, retry {k + 1}")
        r.close()
        time.sleep(min(300, 15 * 2 ** k))
    r.raise_for_status()
    raise RuntimeError(f"GET {url} failed")


def zip_stream(urls):
    """Yield (name, bytes) from the concatenation of URLs holding a (split)
    zip's bytes, by walking local file headers - chesscog's train set is a
    split archive whose entries are self-describing."""
    buf = bytearray()
    it = (chunk for u in urls for chunk in open_stream(u).iter_content(1 << 20))

    def need(n):
        while len(buf) < n:
            try:
                buf.extend(next(it))
            except StopIteration:
                return False
        return True

    if need(4) and bytes(buf[:4]) == b"PK\x07\x08":
        del buf[:4]
    while need(30):
        sig, ver, flag, meth, _, _, crc, cs, us, fl, el = struct.unpack("<IHHHHHIIIHH", bytes(buf[:30]))
        if sig != 0x04034B50:
            return  # central directory reached
        if not need(30 + fl + el):
            return
        name = bytes(buf[30:30 + fl]).decode()
        if flag & 8:
            # Sizes follow the data (data descriptor): inflate until the
            # deflate stream ends, then skip the descriptor.
            if meth != 8:
                raise RuntimeError("stored entry with data descriptor")
            del buf[:30 + fl + el]
            d = zlib.decompressobj(-15)
            parts = []
            while not d.eof:
                if not buf and not need(1):
                    return
                parts.append(d.decompress(bytes(buf)))
                buf.clear()
            rest = d.unused_data
            buf[0:0] = rest
            need(16)
            skip = 16 if bytes(buf[:4]) == b"PK\x07\x08" else 12
            del buf[:skip]
            yield name, b"".join(parts)
            continue
        if not need(30 + fl + el + cs):
            return
        data = bytes(buf[30 + fl + el:30 + fl + el + cs])
        del buf[:30 + fl + el + cs]
        if meth == 8:
            data = zlib.decompress(data, -15)
        elif meth != 0:
            raise RuntimeError(f"zip method {meth}")
        yield name, data


def enc(img):
    return cv2.imencode(".jpg", cv2.cvtColor(img, cv2.COLOR_RGB2BGR),
                        [cv2.IMWRITE_JPEG_QUALITY, 92])[1].tobytes()


class Store:
    """JPEG-encoded crops with labels and a group tag (source/split)."""

    def __init__(self):
        self.occ, self.occ_y, self.occ_g = [], [], []
        self.pc, self.pc_y, self.pc_g = [], [], []

    def add_board(self, img, corners, grid, group, occ_subsample=True):
        ow = C.warp_occupancy(img, corners)
        pw = C.warp_pieces(img, corners)
        occupied = [i for i in range(64) if grid[i] != "."]
        empty = [i for i in range(64) if grid[i] == "."]
        if occ_subsample:
            rng.shuffle(empty)
            empty = empty[:max(8, len(occupied))]
        for i in occupied + empty:
            r, c = divmod(i, 8)
            self.occ.append(enc(C.occupancy_crop(ow, r, c)))
            self.occ_y.append(int(grid[i] != "."))
            self.occ_g.append(group)
        for i in occupied:
            r, c = divmod(i, 8)
            self.pc.append(enc(C.piece_crop(pw, r, c)))
            self.pc_y.append(C.PIECES.index(grid[i]))
            self.pc_g.append(group)


def jitter(corners, sigma):
    return (np.array(corners, np.float32) + np.random.normal(0, sigma, (4, 2))).astype(np.float32)


store = Store()
np.random.seed(3)

# ------------------------------------------------------------ synthetic
OSF = "https://osf.io/download/"
TRAIN_URLS = [OSF + "np56u/", OSF + "z5vgm/"]  # train.z01, train.zip
VAL_URL = OSF + "ydtcs/"


def synth(urls, n, group, jit, cap_bytes=6 << 30):
    # An image's PNG and JSON sit far apart in chesscog's zips (random
    # order), so PNGs wait (compressed, ~1.5 MB each) for their labels.
    pending, done, held = {}, 0, 0
    for name, data in zip_stream(urls):
        if not (name.endswith(".png") or name.endswith(".json")):
            continue
        stem = name.rsplit(".", 1)[0]
        e = pending.setdefault(stem, {})
        e[name.rsplit(".", 1)[1]] = data
        held += len(data)
        while held > cap_bytes:  # drop the oldest waiting image
            k0 = next(iter(pending))
            held -= sum(len(v) for v in pending.pop(k0).values())
        if len(e) < 2 or stem not in pending:
            continue
        held -= sum(len(v) for v in e.values())
        del pending[stem]
        lab = json.loads(e["json"])
        img = cv2.cvtColor(cv2.imdecode(np.frombuffer(e["png"], np.uint8), cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
        chess64 = C.fen_to_chess64(lab["fen"])
        grid = C.chess_to_grid(chess64, 0 if lab["white_turn"] else 2)
        corners = np.array(lab["corners"], np.float32)
        if jit and random.random() < 0.6:
            corners = jitter(corners, 3.0)
        store.add_board(img, corners, grid, group)
        done += 1
        if done % 200 == 0:
            progress(f"{group}: {done} boards, {len(store.occ)} occ / {len(store.pc)} piece crops")
        if done >= n:
            return


progress("streaming chesscog synthetic train split")
synth(TRAIN_URLS, N_SYN, "syn_train", jit=True)
progress("streaming chesscog synthetic val split")
synth([VAL_URL], N_SYN_VAL, "syn_val", jit=False)

# ------------------------------------------------------------ real photos
progress("fetching samryan18/chess-dataset")
SAM = os.environ.get("BP_SAM_DIR") or os.path.join(T, "samryan")
if not os.path.exists(SAM):
    subprocess.check_call(["git", "clone", "--depth", "1", "-q",
                           "https://github.com/samryan18/chess-dataset.git", SAM])
progress("fetching RF100 chess pieces")
RF = os.environ.get("BP_RF_DIR") or os.path.join(T, "rf100")
if not os.path.exists(RF):
    tgz = fetch("https://huggingface.co/datasets/Francesco/chess-pieces-mjzgj/resolve/main/dataset.tar.gz",
                os.path.join(T, "rf100.tgz"))
    with tarfile.open(tgz) as t:
        t.extractall(RF)
RF_ROOT = glob.glob(os.path.join(RF, "**", "chess-pieces-mjzgj"), recursive=True)[0]


def sam_split(name, names_sorted):
    k = names_sorted.index(name) // 10
    return "test" if k % 10 == 0 else ("val" if k % 10 == 5 else "train")


sam_names = sorted(e["file"] for e in LABELS if e["source"] == "samryan")
real_eval = []  # (group, img, corners, grid) kept for board-level eval
for e in (LABELS[:REAL_LIMIT] + [x for x in LABELS if x["source"] == "rf100"][:REAL_LIMIT]
          if REAL_LIMIT else LABELS):
    if e.get("status") != "ok":
        continue
    if e["source"] == "samryan":
        split = sam_split(e["file"], sam_names)
        path = os.path.join(SAM, e["file"])
    else:
        split = {"train": "train", "valid": "val", "test": "test"}[e["split"]]
        path = os.path.join(RF_ROOT, e["file"])
    bgr = cv2.imread(path)
    if bgr is None:
        progress(f"missing {path}")
        continue
    img, _ = C.resize_for_locator(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
    corners = np.array(e["corners"], np.float32) * [img.shape[1], img.shape[0]]
    group = f"{e['source']}_{split}"
    if split == "train":
        # the labelled corners plus two jittered copies: real corners come
        # from the locator, whose error is a few px either way
        store.add_board(img, corners, e["grid"], group, occ_subsample=False)
        for _ in range(2):
            store.add_board(img, jitter(corners, 3.0), e["grid"], group)
    else:
        store.add_board(img, corners, e["grid"], group, occ_subsample=False)
        real_eval.append((group, img, corners, e["grid"]))
progress(f"crops: {len(store.occ)} occupancy, {len(store.pc)} piece")


class Packed:
    """A list of byte strings as one numpy buffer + offsets: DataLoader
    workers fork, and touching a million Python objects there would copy the
    lot into every worker."""

    def __init__(self, items):
        self.off = np.zeros(len(items) + 1, np.int64)
        np.cumsum([len(b) for b in items], out=self.off[1:])
        self.buf = np.frombuffer(b"".join(items), np.uint8)

    def __getitem__(self, i):
        return self.buf[self.off[i]:self.off[i + 1]]

    def __len__(self):
        return len(self.off) - 1


store.occ, store.pc = Packed(store.occ), Packed(store.pc)
store.occ_y, store.pc_y = np.array(store.occ_y), np.array(store.pc_y)
for g in sorted(set(store.occ_g)):
    progress(f"  {g}: {store.occ_g.count(g)} occ, {store.pc_g.count(g)} piece")

# ------------------------------------------------------------ training
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler  # noqa: E402
import torchvision.transforms as TT  # noqa: E402

MEAN, STD = [0.485, 0.456, 0.406], [0.229, 0.224, 0.225]


class Crops(Dataset):
    def __init__(self, blobs, ys, idx, train, hflip):
        self.b, self.y, self.idx = blobs, ys, idx
        aug = [TT.ToPILImage()]
        if train:
            aug += [TT.RandomApply([TT.ColorJitter(0.35, 0.35, 0.35, 0.04)], p=0.8),
                    TT.RandomGrayscale(0.05),
                    TT.RandomApply([TT.GaussianBlur(5, (0.1, 1.6))], p=0.25),
                    TT.RandomAffine(0, translate=(0.04, 0.03), scale=(0.93, 1.07))]
            if hflip:
                aug.append(TT.RandomHorizontalFlip())
        aug += [TT.ToTensor(), TT.Normalize(MEAN, STD)]
        self.t = TT.Compose(aug)

    def __len__(self):
        return len(self.idx)

    def __getitem__(self, k):
        i = self.idx[k]
        img = cv2.imdecode(self.b[i], cv2.IMREAD_COLOR)[:, :, ::-1].copy()
        return self.t(img), int(self.y[i])


def build(k):
    w = torchvision.models.MobileNet_V3_Small_Weights.IMAGENET1K_V1 if PRETRAINED else None
    m = torchvision.models.mobilenet_v3_small(weights=w)
    m.classifier[3] = nn.Linear(m.classifier[3].in_features, k)
    return m


def evaluate(m, blobs, ys, idx, bs=256):
    if not idx:
        return float("nan"), []
    dl = DataLoader(Crops(blobs, ys, idx, False, False), batch_size=bs, num_workers=4)
    m.eval()
    preds = []
    with torch.no_grad():
        for x, _ in dl:
            preds.append(m(x.to(dev)).argmax(1).cpu())
    p = torch.cat(preds).numpy()
    y = np.array([ys[i] for i in idx])
    return float((p == y).mean()), p


def train(name, blobs, ys, groups, k, hflip, epochs, samples_per_epoch, bs, lr):
    samples_per_epoch = max(samples_per_epoch, 2 * bs)
    tr = [i for i, g in enumerate(groups) if g.endswith("_train")]
    evals = {g: [i for i, gg in enumerate(groups) if gg == g]
             for g in sorted(set(groups)) if not g.endswith("_train")}
    # Real crops weigh 40 % of what is drawn, synthetic 60 %.
    real = np.array([not groups[i].startswith("syn") for i in tr])
    wts = np.where(real, 0.4 / max(1, real.sum()), 0.6 / max(1, (~real).sum()))
    sampler = WeightedRandomSampler(torch.tensor(wts, dtype=torch.double), samples_per_epoch, replacement=True)
    dl = DataLoader(Crops(blobs, ys, tr, True, hflip), batch_size=bs, sampler=sampler,
                    num_workers=4, drop_last=True, persistent_workers=True)
    m = build(k).to(dev)
    opt = torch.optim.AdamW(m.parameters(), lr=lr, weight_decay=1e-4)
    steps = epochs * (samples_per_epoch // bs)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=lr, total_steps=steps, pct_start=0.15)
    crit = nn.CrossEntropyLoss(label_smoothing=0.05)
    best, best_sd, hist = -1, None, []
    sel = [g for g in evals if g.endswith("_val") and not g.startswith("syn")]
    for ep in range(epochs):
        m.train()
        tl, n = 0.0, 0
        for x, y in dl:
            x, y = x.to(dev), y.to(dev)
            opt.zero_grad()
            loss = crit(m(x), y)
            loss.backward()
            opt.step()
            sched.step()
            tl += loss.item() * len(y)
            n += len(y)
        accs = {g: evaluate(m, blobs, ys, idx)[0] for g, idx in evals.items()}
        score = float(np.mean([accs[g] for g in sel])) if sel else -accs.get("syn_val", 0)
        hist.append({"epoch": ep, "loss": tl / n, **accs})
        progress(f"{name} ep{ep} loss {tl / n:.4f} " + " ".join(f"{g}={a:.4f}" for g, a in accs.items()))
        if score > best:
            best = score
            best_sd = {k2: v.detach().cpu().clone() for k2, v in m.state_dict().items()}
    m.load_state_dict(best_sd)
    return m, hist


def export(m, name, shape):
    m = m.cpu().eval()
    torch.save(m.state_dict(), os.path.join(W, f"board_photo_{name}.pt"))
    path = os.path.join(W, f"board_photo_{name}.onnx")
    torch.onnx.export(m, torch.zeros(shape), path, input_names=["input"], output_names=["logits"],
                      dynamic_axes={"input": {0: "batch"}, "logits": {0: "batch"}},
                      opset_version=13, dynamo=False)
    try:
        import onnxruntime as ort
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "onnxruntime"], check=False)
        try:
            import onnxruntime as ort
        except ImportError:
            progress(f"exported {path}; onnxruntime unavailable, parity unchecked")
            return m
    x = torch.randn(shape)
    ref = m(x).detach().numpy()
    got = ort.InferenceSession(path, providers=["CPUExecutionProvider"]).run(None, {"input": x.numpy()})[0]
    progress(f"exported {path} ({os.path.getsize(path) // 1024} KB), max|ort-torch| {np.abs(ref - got).max():.2e}")
    return m


scale = (0.35 if CPU else 1.0) * SCALE
occ_m, occ_hist = train("occupancy", store.occ, store.occ_y, store.occ_g, 2, True,
                        epochs=max(1, round((6 if not CPU else 4) * min(1, SCALE * 4))),
                        samples_per_epoch=int(160000 * scale),
                        bs=256, lr=2e-3)
occ_m = export(occ_m, "occupancy", (1, 3, 100, 100))
pc_m, pc_hist = train("pieces", store.pc, store.pc_y, store.pc_g, 12, False,
                      epochs=max(1, round((10 if not CPU else 6) * min(1, SCALE * 4))),
                      samples_per_epoch=int(120000 * scale),
                      bs=128, lr=2e-3)
pc_m = export(pc_m, "pieces", (1, 3, 200, 100))

# ------------------------------------------------ board-level eval (true corners)
occ_m.to(dev).eval()
pc_m.to(dev).eval()
board = {}
with torch.no_grad():
    for group, img, corners, grid in real_eval:
        ow = C.warp_occupancy(img, corners)
        x = torch.from_numpy(C.to_tensor(np.stack([C.occupancy_crop(ow, r, c) for r in range(8) for c in range(8)])))
        occ = occ_m(x.to(dev)).argmax(1).cpu().numpy()
        pred = ["."] * 64
        occi = [i for i in range(64) if occ[i] == 1]
        if occi:
            pw = C.warp_pieces(img, corners)
            x = torch.from_numpy(C.to_tensor(np.stack([C.piece_crop(pw, i // 8, i % 8) for i in occi])))
            pp = pc_m(x.to(dev)).argmax(1).cpu().numpy()
            for i, p in zip(occi, pp):
                pred[i] = C.PIECES[p]
        wrong = sum(pred[i] != grid[i] for i in range(64))
        b = board.setdefault(group, {"boards": 0, "exact": 0, "squares_wrong": 0, "le1": 0})
        b["boards"] += 1
        b["exact"] += wrong == 0
        b["le1"] += wrong <= 1
        b["squares_wrong"] += wrong
for g, b in board.items():
    b["square_acc"] = 1 - b["squares_wrong"] / (64 * b["boards"])
    progress(f"BOARD {g}: {b['exact']}/{b['boards']} exact, {b['le1']} <=1 wrong, squares {b['square_acc']:.4f}")
json.dump({"version": VERSION, "device": dev, "pretrained": PRETRAINED, "n_syn": N_SYN,
           "occupancy": occ_hist, "pieces": pc_hist, "boards_true_corners": board,
           "minutes": (time.time() - t0) / 60}, open(os.path.join(W, "metrics.json"), "w"), indent=1)
progress("DONE")
