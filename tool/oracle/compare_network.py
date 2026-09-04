#!/usr/bin/env python3
"""Compare the app's Lc0 policy against lc0's, one layer at a time.

The app's move comes out of four things stacked up: the input encoding, the
ONNX export of the Maia weights, the pure-Dart ONNX runtime, and the search.
A single end-to-end "does it play well" answer cannot say which of them is
wrong, so this walks the stack:

    A  the app          our planes  -> onnx_runtime_dart  (from dart.json)
    B  reference run    our planes  -> onnxruntime
    C  reference run    lc0's planes-> onnxruntime
    D  lc0 itself       lc0's planes-> lc0's own weights

    A vs B  isolates the pure-Dart ONNX runtime
    B vs C  isolates the input encoding
    C vs D  isolates the ONNX export of the weights (and the policy indexing)

Each stage produces a probability distribution over the legal moves, so the
comparisons are like-for-like: top-1 agreement, and the largest per-move
difference in probability.

    python3 tool/oracle/compare_network.py --dart build/oracle/dart.json \
        --onnx maia-1900.onnx [--lc0 ./lc0 --weights maia-1900.pb.gz]
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from reference_encoder import encode  # noqa: E402

# The move vocabulary the networks were trained against, fetched from
# lczero-training rather than transcribed.
POLICY_INDEX_URL = ("https://raw.githubusercontent.com/LeelaChessZero/"
                    "lczero-training/master/tf/policy_index.py")


def load_policy_index(path):
    namespace = {}
    exec(open(path).read(), namespace)
    moves = namespace["policy_index"]
    assert len(moves) == 1858, f"expected 1858 moves, got {len(moves)}"
    return {move: i for i, move in enumerate(moves)}


def mirror_move(uci):
    def flip(square):
        return f"{square[0]}{9 - int(square[1])}"
    return flip(uci[:2]) + flip(uci[2:4]) + uci[4:]


def planes_to_tensor(planes):
    """112 (mask, value) pairs -> the [1, 112, 8, 8] float tensor."""
    out = np.zeros((112, 64), dtype=np.float32)
    for p, (mask, value) in enumerate(planes):
        if not mask:
            continue
        bits = np.array([(mask >> i) & 1 for i in range(64)], dtype=np.float32)
        out[p] = bits * value
    return out.reshape(1, 112, 8, 8)


def softmax_over(logits):
    m = max(logits.values())
    weights = {k: np.exp(v - m) for k, v in logits.items()}
    total = sum(weights.values())
    return {k: float(v / total) for k, v in weights.items()}


def run_onnx(session, tensor, legal, black, index):
    names = [o.name for o in session.get_outputs()]
    policy_name = next(n for n in names if "policy" in n)
    outputs = session.run(None, {session.get_inputs()[0].name: tensor})
    logits = outputs[names.index(policy_name)].reshape(-1)
    raw = {}
    for move in legal:
        key = mirror_move(move) if black else move
        i = index.get(key)
        raw[move] = float(logits[i]) if i is not None else -100.0
    return softmax_over(raw)


class Lc0:
    """lc0 driven over UCI, one root evaluation per position."""

    def __init__(self, binary, weights, backend="eigen"):
        self.proc = subprocess.Popen(
            [binary, f"--weights={weights}", f"--backend={backend}",
             "--verbose-move-stats", "--policy-softmax-temp=1.0",
             "--minibatch-size=1", "--threads=1", "--cpuct=1.0"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1)
        self._send("uci")
        self._until("uciok")

    def _send(self, line):
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def _until(self, token, collect=False):
        lines = []
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError(f"lc0 exited before {token!r}")
            if collect:
                lines.append(line.rstrip())
            if line.startswith(token) or line.strip() == token:
                return lines

    def policy(self, moves):
        self._send("ucinewgame")
        self._send("isready")
        self._until("readyok")
        played = " moves " + " ".join(moves) if moves else ""
        self._send(f"position startpos{played}")
        self._send("go nodes 1")
        lines = self._until("bestmove", collect=True)

        # info string e2e4  (322 ) N:  0 (+ 0) (P: 12.34%) (Q: ...) ...
        found = {}
        for line in lines:
            if not line.startswith("info string "):
                continue
            body = line[len("info string "):].strip()
            move = body.split()[0]
            if "(P:" not in body or move == "node":
                continue
            share = body.split("(P:")[1].split("%")[0].strip()
            try:
                found[move] = float(share) / 100.0
            except ValueError:
                continue
        return found

    def close(self):
        try:
            self._send("quit")
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()


def compare(label, left, right, cases):
    """Report top-1 agreement and the worst per-move probability gap."""
    top1 = 0
    counted = 0
    worst = (0.0, None)
    for case in cases:
        a, b = left.get(case), right.get(case)
        if not a or not b:
            continue
        counted += 1
        shared = set(a) & set(b)
        if not shared:
            continue
        if max(a, key=a.get) == max(b, key=b.get):
            top1 += 1
        gap = max(abs(a[m] - b[m]) for m in shared)
        if gap > worst[0]:
            worst = (gap, case)
    if not counted:
        print(f"  {label:<44} (not run)")
        return True
    ok = top1 == counted and worst[0] < 0.02
    print(f"  {label:<44} top-1 {top1:>3}/{counted}   "
          f"worst move gap {worst[0]:6.2%}"
          f"{'' if worst[1] is None else '  (' + worst[1] + ')'}"
          f"   {'ok' if ok else 'MISMATCH'}")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dart", required=True)
    ap.add_argument("--onnx", required=True)
    ap.add_argument("--policy-index", required=True)
    ap.add_argument("--lc0")
    ap.add_argument("--weights")
    ap.add_argument("--backend", default="eigen")
    args = ap.parse_args()

    index = load_policy_index(args.policy_index)
    dart_cases = json.load(open(args.dart))["cases"]

    import onnxruntime as ort
    session = ort.InferenceSession(args.onnx,
                                   providers=["CPUExecutionProvider"])

    a, b, c, d = {}, {}, {}, {}
    lc0 = Lc0(args.lc0, args.weights, args.backend) if args.lc0 else None

    for case in dart_cases:
        name = case["name"]
        if "policy" not in case:
            continue
        black = case["fen"].split()[1] == "b"
        legal = case["legal"]
        a[name] = case["policy"]

        ours = [(int(p["mask"], 16), float(p["value"])) for p in case["planes"]]
        b[name] = run_onnx(session, planes_to_tensor(ours), legal, black, index)

        theirs = encode(case["moves"])
        c[name] = run_onnx(session, planes_to_tensor(theirs), legal, black,
                           index)

        if lc0:
            got = lc0.policy(case["moves"])
            if got:
                total = sum(got.values()) or 1.0
                d[name] = {m: v / total for m, v in got.items()}
        print(".", end="", flush=True)
    print()
    if lc0:
        lc0.close()

    names = [case["name"] for case in dart_cases if "policy" in case]
    print(f"\n{len(names)} positions\n")
    ok = True
    ok &= compare("A vs B  pure-Dart ONNX runtime", a, b, names)
    ok &= compare("B vs C  input encoding", b, c, names)
    ok &= compare("C vs D  ONNX export of the weights", c, d, names)
    ok &= compare("A vs D  the app, end to end, against lc0", a, d, names)

    unmapped = {m for case in dart_cases for m in case.get("unmapped", [])}
    if unmapped:
        print(f"\nlegal moves with no policy index: "
              f"{len(unmapped)} distinct, e.g. {sorted(unmapped)[:6]}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
