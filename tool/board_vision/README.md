# Board vision: the square classifier

`assets/models/board_squares.onnx` classifies one board square as empty or one
of the twelve pieces. `lib/vision/board_recognizer.dart` finds the board in an
image, cuts it into 64 squares and runs this model on them through the
pure-Dart ONNX interpreter (`package:onnx_runtime_dart`), so recognition is
offline and identical on every platform, web included.

The model is trained on synthetic boards only: nine SVG piece sets plus
Unicode chess glyphs from five permissively licensed fonts, drawn two ways —
as screens draw boards (flat coloured squares, the app's and the usual
sites' themes, highlights, coordinates) and as print does (ink on paper:
diagonal, crossed or straight hatching, stipple, halftone dots, ordered
dither or grey dark squares; frames, outside coordinates and captions; inked
pieces, sometimes bold, sometimes with a white rim on hatched squares). Each
board then goes through what capturing it does: rendered at 12–26 px a square
and zoomed, or shrunk to a thumbnail; stretched along one axis; rotated up to
2° and put in slight perspective; ink spread or thinned; halftoned; uneven
light and paper grain; blur, noise, tone, and JPEG down to quality 8. The
crops carry the lattice error the detector can make. Every training source is
permissively licensed — see [Training data licences](#training-data-licences).

## Retrain

Needs Python 3 with `torch`, `numpy`, `Pillow`, `onnx` and `cairosvg`
(`pip install --user cairosvg`), the DejaVu fonts (`fonts-dejavu-core` on
Debian/Ubuntu) and the OFL fonts `tool/board_vision/fonts/fetch.sh`
downloads (not committed).

```sh
tool/board_vision/fonts/fetch.sh

# training squares: 64 per board, one worker process (~150 MB) per shard
python3 tool/board_vision/gen.py --out /tmp/bv_data --boards 2500 --shards 24 --seed 11

# benchmark boards (PNG + FEN + true rect), also usable with other recognizers
python3 tool/board_vision/bench.py --out /tmp/bv_bench            # capture damage
python3 tool/board_vision/bench.py --out /tmp/bv_bench_v1 --plain  # first recipe

# how well it generalises to a piece set it has never seen
python3 tool/board_vision/train.py --data /tmp/bv_data --holdout papercut \
    --bench /tmp/bv_bench

# the shipped model, trained on every source
python3 tool/board_vision/train.py --data /tmp/bv_data --bench /tmp/bv_bench \
    --epochs 18 --batch 512 --lr 3e-3 --export assets/models/board_squares.onnx

# test boards for test/board_vision_test.dart
python3 tool/board_vision/make_fixtures.py

# end to end in Dart (detection + classification + orientation) on a bench
BV_BENCH=/tmp/bv_bench flutter test tool/board_vision/bench_e2e_test.dart

# end to end on real diagrams named by their placement (see the file)
BV_REAL=/path/to/diagrams flutter test tool/board_vision/real_eval_test.dart
```

The shipped model was trained on Kaggle (`kaggle/`, account chr1s4, P100):
60k boards (3.8M squares) generate in about 35 minutes on four cores and
train for 18 epochs in about 45 minutes, where the same on a shared
two-thread CPU would take a day or more. `kaggle/build_dataset.sh` packs the
scripts, the piece sets pre-rendered to PNG (`prerender.py`; the kernel then
needs no cairosvg) and the fonts into a private dataset;
`kaggle/kernel.py` generates, trains and exports, and
`train.py --init model.pt --epochs 0 --export ...` re-exports its weights
locally. Locally, `train.py` uses two CPU threads and memory-maps the squares
from disk (merged once into `merged_<n>.npy` next to the shards).

### Tried, not shipped

Two further runs added, on top of the shipped recipe, per-piece-type sizes
and shape warps, restyled (grey, shadowed) screen pieces, grey book pieces,
ink-threshold fixes for firi and rhosgfx (`BV_EXTRA_AUG=1`), 80k boards, and
in the second also train-time shift/scale/tone jitter (`train.py --augment`).
Neither beat the shipped model on the benchmarks (classification with the
true rect, `bench.py` defaults / `--plain` recipe):

| Model | hard bench (224 boards) | plain bench (120 boards) |
|---|---|---|
| first model (v1 net, 12k boards) | 89.47 % squares, 91 boards | 99.79 %, 113 |
| **shipped** (v2 net, 60k boards) | **98.47 %, 177** | **99.88 %, 117** |
| + extra augmentation, 80k boards | 98.44 %, 177 | 99.88 %, 117 |
| + train-time jitter | 98.21 %, 169 | 99.38 %, 111 |

Known weakness of the shipped recipe: at low ink thresholds firi's black
pieces (light with a dark half) ink like its white ones, which is label
noise for firi print boards; the `BV_EXTRA_AUG` path renders firi in grey
levels instead.

## Keep in sync with Dart

- `render.CLASSES` ↔ `boardSquareClasses` (output order).
- `render.grayscale` and `render.cell_to_input` ↔ `GrayImage.fromRgba` and
  `cellInput`: integer luminance `(299 R + 587 G + 114 B) / 1000`, then
  area-averaging each cell to 32×32 with the same floor-based bounds, then
  `/ 255`. Cells may be non-square (`w` ≠ `h`). A change on one side needs the
  other and a retrain.
- Input `input` `[N, 1, 32, 32]` float32 (N dynamic, the app uses 64), output
  `logits` `[N, 13]`. Only Conv, Relu, MaxPool, Flatten and Gemm are used
  (BatchNorm is folded into the convolutions at export). Architecture `v2`:
  conv 24 → pool → conv 48 → pool → conv 64 → conv 64 → pool → FC 128 → 13,
  about 210k parameters (0.8 MB).

## After the network

`BoardRecognizer` does not take the argmax blindly (`decodeSquares`): a pawn
on the top or bottom row becomes the square's best non-pawn class, a second
king of one colour its next-best class, and a king the network missed goes to
the likeliest square if that square gives it at least 10 %. Diagrams without
kings (study fragments) stay without them.

The detector fits the 8×8 lattice of square edges (on a copy at most 400 px
across, then refined at full resolution). Around that:

- Rows are searched only at steps near the column step, so a block of text
  lines cannot stand in for them; lattices up to 1.7:1 are accepted when both
  directions are unmistakable (stretched photos).
- When no upright lattice is found, profiles sheared by ±1° and ±2° are
  tried, for boards scanned or photographed slightly turned; the result is the
  axis-aligned rect through the board's centre, which is what the classifier
  is trained to read.
- Lines too faint to trust alone (a dithered or noisy scan) are accepted only
  if every row and column of the squares alternates between two tones.
- The lattice one square off in each direction is checked the same way: a
  frame, outside coordinates, a UI panel or a neighbouring diagram can supply
  a seventh line, but only the true board alternates along all sixteen lines.
- Transparent pixels are composited over white.

## Training data licences

The model is trained only on images rendered from these sources. All are
permissive; the CC BY 4.0 sets require credit to their authors, which this
section and the app's notices give.

| Source | Author | Licence | Used as |
|---|---|---|---|
| chessnut pieces | [Alexis Luengas](https://github.com/LexLuengas/chessnut-pieces) | Apache-2.0 | SVG piece set |
| rhosgfx pieces | [RhosGFX](https://rhosgfx.itch.io/) | CC0 1.0 | SVG piece set |
| fantasy pieces | [Maurizio Monge](https://github.com/maurimo/chess-art) | MIT | SVG piece set |
| spatial pieces | [Maurizio Monge](https://github.com/maurimo/chess-art) | MIT | SVG piece set |
| celtic pieces | [Maurizio Monge](https://github.com/maurimo/chess-art) | MIT | SVG piece set |
| kiwen-suwi pieces | [neverRare](https://github.com/neverRare) | CC BY 4.0 | SVG piece set |
| totoy pieces | Kosal Sen | CC BY 4.0 | SVG piece set |
| papercut pieces | [Nikolay Anzarov](https://nikoichu.itch.io/) | CC BY 4.0 | SVG piece set |
| firi pieces | [James Faure](https://github.com/jfaure/Firi-pieceset) | CC BY 4.0 | SVG piece set (`pieces/firi/`) |
| DejaVu Sans, Sans Bold, Serif, Serif Bold | DejaVu fonts team (Bitstream Vera) | Bitstream Vera licence; DejaVu changes public domain | chess glyphs U+2654–265F (Sans), coordinates and captions |
| [Noto Sans Symbols 2](https://github.com/notofonts/symbols) | The Noto Project Authors | SIL OFL 1.1 | chess glyphs |
| [JuliaMono](https://github.com/cormullion/juliamono) 0.063 | The JuliaMono Project Authors (Cormullion) | SIL OFL 1.1 | chess glyphs |
| [Fairfax HD](https://github.com/kreativekorp/open-relay/tree/master/FairfaxHD) | Kreative Software | SIL OFL 1.1 | chess glyphs |
| [GNU Unifont](https://unifoundry.com/unifont/) 15.1.05 | Roman Czyborra, Paul Hardy et al. | SIL OFL 1.1 (upstream is dual GPL-2.0+ with font embedding exception / OFL 1.1 since 13.0.04; the OFL option is used — the font's own licence field says so) | chess glyphs |

The first eight piece sets are the ones in `assets/pieces/`; they and firi
are distributed by [Lichess](https://github.com/lichess-org/lila/blob/master/COPYING.md),
which lists the authors and licences above. The firi SVGs here are Lichess's
copies (`public/piece/firi`); the upstream repository carries the CC BY 4.0
text.

Board colours are plain RGB values; the hatching, stippling, dots, dither,
paper, noise and compression are generated. No photographs, screenshots or
third-party datasets are used for training.

Checked and not used: GNU FreeFont (GPL-3.0 only), the Debian `fonts-unifont`
package (its copyright file lists only the GPL, so the upstream build is
fetched instead), Quivira (the font says "All Rights Reserved"), DejaVu Sans
Mono (the same chess glyphs as DejaVu Sans), Kreative Square and Noto Sans
Math (no chess glyphs), and the Lichess sets under GPL, AGPL, CC BY-SA,
CC BY-NC-SA or "freeware" terms (cburnett, merida, alpha, leipzig, maestro,
pirouetti, companion, chess7 and others). Add a source only if it is MIT,
Apache, BSD, CC0, CC BY, OFL or public domain, and list it here, in
NOTICE.md and in THIRD_PARTY_LICENSES.md.
