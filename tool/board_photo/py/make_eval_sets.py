"""Held-out evaluation sets for tool/board_photo/eval_e2e_test.dart.

Writes <out>/<set>/labels.tsv plus the photos, shrunk to at most 1600 px on
the long side (what the app's scan screen decodes them at), for:

  chesscog27  chesscog's 27 real test photos (transfer-learning set) - an
              unseen physical set; the camera side is known from white_turn
  samryan     samryan18/chess-dataset held-out split (blocks of ten sorted
              names, every tenth block - the kernel's split), labels ok only
  rf100       RF100 chess-pieces test split, labels ok only; orientation
              unknown (boxes carry no board coordinates), grid scored only

  python make_eval_sets.py --labels real_labels.json --samryan DIR \
      --rf100 DIR --chesscog-tl DIR --out DIR
"""
import argparse, glob, json, os, sys

import cv2

sys.path.insert(0, os.path.dirname(__file__))
import crops as C


def shrink_copy(src, dst, max_side=1600):
    img = cv2.imread(src)  # EXIF applied
    h, w = img.shape[:2]
    s = min(1.0, max_side / max(h, w))
    if s < 1:
        img = cv2.resize(img, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA)
    cv2.imwrite(dst, img, [cv2.IMWRITE_JPEG_QUALITY, 92])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--labels", required=True)
    ap.add_argument("--samryan")
    ap.add_argument("--rf100")
    ap.add_argument("--chesscog-tl")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    labels = json.load(open(a.labels))["images"]
    sets = {}
    if a.chesscog_tl:
        rows = []
        for p in sorted(glob.glob(os.path.join(a.chesscog_tl, "*.png"))):
            lab = json.load(open(p[:-4] + ".json"))
            rot = 0 if lab["white_turn"] else 2
            grid = C.chess_to_grid(C.fen_to_chess64(lab["fen"]), rot)
            rows.append((p, os.path.basename(p)[:-4] + ".jpg", grid, rot))
        sets["chesscog27"] = rows
    sam = sorted(e["file"] for e in labels if e["source"] == "samryan")
    rows_s, rows_r = [], []
    for e in labels:
        if e.get("status") != "ok":
            continue
        if e["source"] == "samryan" and a.samryan:
            k = sam.index(e["file"]) // 10
            if k % 10 == 0:
                rows_s.append((os.path.join(a.samryan, e["file"]),
                               os.path.basename(e["file"]).rsplit(".", 1)[0] + ".jpg",
                               e["grid"], e["rotation"]))
        if e["source"] == "rf100" and a.rf100 and e["split"] == "test":
            rows_r.append((os.path.join(a.rf100, e["file"]),
                           os.path.basename(e["file"]), e["grid"], -1))
    if rows_s:
        sets["samryan"] = rows_s
    if rows_r:
        sets["rf100"] = rows_r
    for name, rows in sets.items():
        d = os.path.join(a.out, name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "labels.tsv"), "w") as f:
            for src, dst, grid, rot in rows:
                if not os.path.exists(os.path.join(d, dst)):
                    shrink_copy(src, os.path.join(d, dst))
                f.write(f"{dst}\t{grid}\t{rot}\n")
        print(name, len(rows))


if __name__ == "__main__":
    main()
