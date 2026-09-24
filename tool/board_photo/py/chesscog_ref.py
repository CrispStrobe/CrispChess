"""Reference board corners from chesscog's own Python localiser.

Runs chesscog.corner_detection.find_corners exactly as
chesscog.recognition.ChessRecognizer.predict does (RGB image resized to 1200 px
wide, then handed to find_corners, which converts it with COLOR_BGR2GRAY - so
the red and blue weights are swapped, as in chesscog's recognition pipeline),
and writes, per image:

  <out>/<stem>.ppm   the 1200-px-wide RGB image both localisers see
  <out>/<stem>.json  {"corners": [[x, y] x4] | null, "seeds": [...], "ms": t}

corners are in the 1200-px image (TL, TR, BR, BL). Several RANSAC seeds are run
so the spread of Python's own answer is known (the RANSAC is random).

  CHESSCOG_REPO=/path/to/chesscog python chesscog_ref.py --out DIR img1 img2 ...

Needs numpy, opencv-python, scikit-learn, torch (chesscog.core imports it),
pyyaml. chesscog: https://github.com/georg-wolflein/chesscog (MIT).
"""
import argparse, json, os, sys, time, types
from pathlib import Path

import numpy as np
import cv2


def _install_recap_shim():
    """chesscog needs `recap` for config loading; a tiny stand-in suffices."""
    import yaml
    translators = {}

    def URI(p):
        p = str(p)
        if "://" in p:
            s, rest = p.split("://", 1)
            return translators[s] / rest if rest else translators[s]
        return Path(p)

    class CfgNode(dict):
        def __getattr__(self, k):
            try:
                return self[k]
            except KeyError:
                raise AttributeError(k)

        @staticmethod
        def _wrap(v):
            if isinstance(v, dict):
                return CfgNode({k: CfgNode._wrap(x) for k, x in v.items()})
            if isinstance(v, list):
                return [CfgNode._wrap(x) for x in v]
            return v

        @staticmethod
        def _merge(a, b):
            for k, v in b.items():
                if isinstance(v, dict) and isinstance(a.get(k), dict):
                    CfgNode._merge(a[k], v)
                else:
                    a[k] = v
            return a

        @classmethod
        def load_yaml_with_base(cls, path):
            d = yaml.safe_load(open(URI(path))) or {}
            base = d.pop("_BASE_", None)
            out = cls._merge(dict(cls.load_yaml_with_base(base)) if base else {}, d)
            return cls._wrap(out)

    recap = types.ModuleType("recap")
    pm = types.ModuleType("recap.path_manager")
    pm.URI = URI
    pm.register_translator = lambda name, path: translators.__setitem__(name, Path(path))
    recap.URI, recap.CfgNode, recap.path_manager = URI, CfgNode, pm
    sys.modules["recap"], sys.modules["recap.path_manager"] = recap, pm
    sys.modules["google_drive_downloader"] = types.SimpleNamespace(GoogleDriveDownloader=None)


def load_localiser(repo):
    _install_recap_shim()
    sys.path.insert(0, str(repo))
    import sklearn.cluster as skc
    import chesscog.corner_detection.detect_corners as dc
    from recap import CfgNode as CN
    ac = skc.AgglomerativeClustering
    # scikit-learn >= 1.4 renamed `affinity` and wants a scalar metric callable.
    dc.AgglomerativeClustering = lambda n_clusters, affinity, linkage: ac(
        n_clusters=n_clusters, metric=affinity, linkage=linkage)
    dc.pairwise_distances = lambda a, b, metric: metric(a[:, None, 0], b[None, :, 0])
    cfg = CN.load_yaml_with_base(str(Path(repo) / "config" / "corner_detection.yaml"))
    return dc, cfg


def write_ppm(path, rgb):
    h, w, _ = rgb.shape
    with open(path, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (w, h))
        f.write(np.ascontiguousarray(rgb, dtype=np.uint8).tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--repo", default=os.environ.get("CHESSCOG_REPO"))
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--no-ppm", action="store_true")
    ap.add_argument("images", nargs="+")
    a = ap.parse_args()
    dc, cfg = load_localiser(a.repo)
    os.makedirs(a.out, exist_ok=True)
    for p in a.images:
        stem = Path(p).stem
        bgr = cv2.imread(p)  # applies EXIF orientation
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        rgb, _ = dc.resize_image(cfg, rgb)
        if not a.no_ppm:
            write_ppm(os.path.join(a.out, stem + ".ppm"), rgb)
        runs = []
        for seed in range(a.seeds):
            np.random.seed(seed)
            t = time.perf_counter()
            try:
                c = dc.find_corners(cfg, rgb).tolist()
            except Exception as e:  # ChessboardNotLocatedException and friends
                c = None
            runs.append({"seed": seed, "corners": c, "ms": (time.perf_counter() - t) * 1000})
        ok = [r["corners"] for r in runs if r["corners"] is not None]
        spread = None
        if len(ok) > 1:
            arr = np.array(ok)
            spread = float(np.abs(arr - arr[0]).max())
        json.dump({"file": p, "size": [rgb.shape[1], rgb.shape[0]],
                   "corners": runs[0]["corners"], "runs": runs, "seed_spread_px": spread},
                  open(os.path.join(a.out, stem + ".json"), "w"))
        print(stem, "ok" if runs[0]["corners"] else "FAIL",
              f"{runs[0]['ms']:.0f} ms", f"spread={spread}", flush=True)


if __name__ == "__main__":
    main()
