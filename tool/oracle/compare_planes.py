#!/usr/bin/env python3
"""Diff the app's encoder against the transcription of lc0's.

    python3 tool/oracle/compare_planes.py dart.json [positions.txt]

Reports, per plane index, how many of the test positions disagree — a plane
that is wrong shows up as a column, not as scattered noise, which is what
separates a systematic encoding bug from a one-position accident.
"""
import collections
import json
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from reference_encoder import encode  # noqa: E402

PLANE_NAMES = {
    104: "castling: our queenside", 105: "castling: our kingside",
    106: "castling: their queenside", 107: "castling: their kingside",
    108: "side to move is black", 109: "rule-50 counter",
    110: "(unused, zeros)", 111: "all ones",
}


def _tensor(plane):
    """The 64 floats a (mask, value) plane expands to."""
    mask, value = plane
    return tuple(value if mask >> i & 1 else 0.0 for i in range(64))


def plane_name(i):
    if i in PLANE_NAMES:
        return PLANE_NAMES[i]
    slot, within = divmod(i, 13)
    kind = (["our pawns", "our knights", "our bishops", "our rooks",
             "our queens", "our king", "their pawns", "their knights",
             "their bishops", "their rooks", "their queens", "their king",
             "repetition"])[within]
    return f"history slot {slot}: {kind}"


def main():
    dart = json.load(open(sys.argv[1]))["cases"]
    failures = collections.Counter()
    examples = {}
    total = 0

    for case in dart:
        total += 1
        want = encode(case["moves"])
        got = [(int(p["mask"], 16), float(p["value"])) for p in case["planes"]]
        for i, (w, g) in enumerate(zip(want, got)):
            # Compare the 64 numbers the network actually receives, not the
            # (mask, value) pair that carries them: lc0 fills a plane with a
            # zero rule-50 count as mask=all/value=0, which is the same tensor
            # as an empty mask, and a difference there is not a difference.
            if _tensor(w) == _tensor(g):
                continue
            if True:
                failures[i] += 1
                examples.setdefault(i, (case["name"], w, g))

    print(f"{total} positions, {len(failures)} planes disagree\n")
    if not failures:
        print("the encoder matches lc0 on every plane of every position")
        return 0

    print(f"{'plane':>5}  {'n':>4}/{total}  {'meaning':<34} example")
    for i in sorted(failures):
        name, w, g = examples[i]
        print(f"{i:>5}  {failures[i]:>4}/{total}  {plane_name(i):<34} "
              f"{name}: lc0 mask={w[0]:#x} val={w[1]:g} | "
              f"ours mask={g[0]:#x} val={g[1]:g}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
