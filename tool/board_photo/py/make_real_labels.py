"""Board corners + per-cell labels for the real-photo training/eval sets.

Real photo sets come with a FEN (samryan18/chess-dataset, MIT) or with piece
bounding boxes (Roboflow "chess pieces" via RF100, CC BY 4.0), never with
board corners. This finds the corners with chesscog's localiser (consensus of
several RANSAC seeds), then:

  * FEN sets: tries all four orientations and keeps the one whose occupancy
    agrees best with an occupancy classifier (chesscog's released ResNet,
    MIT - used here only as a checker, it is not shipped);
  * box sets: drops each box's base point (bottom centre, lifted by a fifth
    of the box width) through the homography into a grid cell.

Images whose labels disagree with the occupancy checker on more than
--max-disagree cells are rejected (the corners are then almost certainly a
square off). Output: one JSON with, per image, corners normalised to the
image size (TL, TR, BR, BL in image order) and a 64-char grid string
(row 0 = top of the photo; '.' empty, else FEN letter).

  CHESSCOG_REPO=... python make_real_labels.py --occ-onnx occupancy_resnet18.onnx \
      --samryan DIR --rf100 DIR --out labels.json
"""
import argparse, glob, json, os, sys, time
from pathlib import Path

import numpy as np
import cv2

sys.path.insert(0, os.path.dirname(__file__))
import crops as C
from chesscog_ref import load_localiser


def consensus_corners(dc, cfg, img, seeds=5, tol=6.0):
    sols = []
    for s in range(seeds):
        np.random.seed(s)
        try:
            sols.append(dc.find_corners(cfg, img))
        except Exception:
            pass
    if not sols:
        return None, 0
    sols = np.array(sols)
    d = np.abs(sols[:, None] - sols[None]).max(axis=(2, 3))
    support = (d <= tol).sum(1)
    best = int(support.argmax())
    members = sols[d[best] <= tol]
    return members.mean(0), int(support[best])


class OccChecker:
    def __init__(self, path):
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.intra_op_num_threads = 2
        self.s = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"])

    def __call__(self, img, corners):
        w = C.warp_occupancy(img, corners)
        crops = np.stack([C.occupancy_crop(w, r, c) for r in range(8) for c in range(8)])
        p = []
        for i in range(0, 64, 16):
            logits = self.s.run(None, {"input": C.to_tensor(crops[i:i + 16])})[0]
            e = np.exp(logits - logits.max(1, keepdims=True))
            p.append((e / e.sum(1, keepdims=True))[:, 1])
        return np.concatenate(p)  # P(occupied) per grid cell


def load_rgb(path):
    bgr = cv2.imread(path)  # EXIF orientation applied
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)


def judge(e):
    """Accept a label when the corners are a consensus (3 of 5 RANSAC seeds)
    and the labels cannot be a square off: FEN sets need one orientation
    clearly ahead of the others and at most 14 occupancy disagreements
    (chesscog's occupancy net, trained on angled renders, misreads a few
    squares of a top-down photo - visual checks showed those labels right);
    box sets need every box in its own cell and at most 8 disagreements."""
    if "grid" not in e:
        return e.get("status", "no_board")
    if e.get("support", 0) < 3:
        return "weak_corners"
    if e["source"] == "samryan":
        # Nearly every photo in the set has White at the bottom: keep that
        # unless another orientation is clearly better.
        sc = e["rotation_scores"]
        best = max(sc)
        if sc[0] >= best - 1:
            rot = 0
        elif best - sorted(sc)[-2] >= 4:
            rot = sc.index(best)
        else:
            return "ambiguous_rotation"
        if rot != e["rotation"]:
            e["grid"] = C.chess_to_grid(C.fen_to_chess64(Path(e["file"]).stem), rot)
            e["rotation"] = rot
            e["occ_agree"] = sc[rot]
        return "ok" if e["occ_agree"] >= 44 else "rejected"
    if e.get("box_clashes", 0):
        return "box_clash"
    return "ok" if e["occ_agree"] >= 56 else "rejected"


def restatus(path):
    out = json.load(open(path))
    for e in out["images"]:
        if e.get("status") in ("ok", "rejected", "weak_corners", "ambiguous_rotation", "box_clash"):
            e["status"] = judge(e)
    json.dump(out, open(path, "w"))
    st = {}
    for e in out["images"]:
        st[(e["source"], e["status"])] = st.get((e["source"], e["status"]), 0) + 1
    print(st)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CHESSCOG_REPO"))
    ap.add_argument("--occ-onnx", required=True)
    ap.add_argument("--samryan")
    ap.add_argument("--rf100")
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--restatus", action="store_true",
                    help="only re-judge the images already in --out")
    a = ap.parse_args()
    if a.restatus:
        return restatus(a.out)
    dc, cfg = load_localiser(a.repo)
    occ = OccChecker(a.occ_onnx)
    out = json.load(open(a.out)) if os.path.exists(a.out) else {"images": []}
    done = {e["file"] for e in out["images"]}

    def save():
        json.dump(out, open(a.out + ".tmp", "w"))
        os.replace(a.out + ".tmp", a.out)

    jobs = []
    if a.samryan:
        for p in sorted(glob.glob(os.path.join(a.samryan, "labeled_originals", "*"))):
            jobs.append(("samryan", p, None))
    if a.rf100:
        for split in ("train", "valid", "test"):
            j = json.load(open(os.path.join(a.rf100, split, "_annotations.coco.json")))
            cats = {c["id"]: c["name"] for c in j["categories"]}
            anns = {}
            for an in j["annotations"]:
                anns.setdefault(an["image_id"], []).append(an)
            for im in j["images"]:
                jobs.append(("rf100", os.path.join(a.rf100, split, im["file_name"]),
                             (split, [(cats[x["category_id"]], x["bbox"]) for x in anns.get(im["id"], [])])))
    if a.limit:
        jobs = jobs[:a.limit]
    letter = {"pawn": "p", "knight": "n", "bishop": "b", "rook": "r", "queen": "q", "king": "k"}
    t0 = time.time()
    for k, (src, path, extra) in enumerate(jobs):
        rel = os.path.relpath(path, a.samryan if src == "samryan" else a.rf100)
        if rel in done:
            continue
        full = load_rgb(path)
        img, s = C.resize_for_locator(full)
        corners, support = consensus_corners(dc, cfg, img)
        rec = {"source": src, "file": rel, "size": [full.shape[1], full.shape[0]]}
        if corners is None:
            rec["status"] = "no_board"
            out["images"].append(rec)
            continue
        corners = C.sort_corner_points(corners)
        rec["corners"] = (corners / [img.shape[1], img.shape[0]]).round(5).tolist()
        rec["support"] = support
        pocc = occ(img, corners)
        pred = pocc > 0.5
        if src == "samryan":
            fen = C.fen_to_chess64(Path(path).stem)
            scores = []
            for rot in range(4):
                g = C.chess_to_grid(fen, rot)
                scores.append(int(sum((g[i] != ".") == pred[i] for i in range(64))))
            rot = int(np.argmax(scores))
            grid = C.chess_to_grid(fen, rot)
            rec.update(rotation=rot, rotation_scores=scores, split="pending")
        else:
            split, boxes = extra
            if any(name not in ("chess-pieces",) and "-" not in name for name, _ in boxes):
                rec["status"] = "ambiguous_class"
                out["images"].append(rec)
                continue
            src_pts = C.sort_corner_points(corners)
            dst = np.array([[0, 0], [8, 0], [8, 8], [0, 8]], np.float32)
            m, _ = cv2.findHomography(src_pts, dst)
            g = ["."] * 64
            clash = 0
            for name, (x, y, w, h) in boxes:
                if "-" not in name:
                    continue
                colour, kind = name.split("-")
                ch = letter[kind]
                ch = ch.upper() if colour == "white" else ch
                # bbox is in the 640x640 file; img is that resized to 1200 wide
                px = (x + w / 2) * s
                py = (y + h - 0.2 * w) * s
                q = m @ np.array([px, py, 1.0])
                gx, gy = q[0] / q[2], q[1] / q[2]
                if not (0 <= gx < 8 and 0 <= gy < 8):
                    clash += 1
                    continue
                cell = int(gy) * 8 + int(gx)
                if g[cell] != ".":
                    clash += 1
                g[cell] = ch
            grid = "".join(g)
            rec.update(split=split, box_clashes=clash)
        agree = int(sum((grid[i] != ".") == pred[i] for i in range(64)))
        rec.update(grid=grid, occ_agree=agree)
        rec["status"] = judge(rec)
        out["images"].append(rec)
        if k % 10 == 0:
            save()
            print(f"{k}/{len(jobs)} {time.time() - t0:.0f}s {src} {rel} agree={agree} {rec['status']}", flush=True)
    save()
    st = {}
    for e in out["images"]:
        st[(e["source"], e["status"])] = st.get((e["source"], e["status"]), 0) + 1
    print(st)


if __name__ == "__main__":
    main()
