# Performance harnesses

Two small benchmarks that back the perf work on engine move latency and on the
game screen's per-rebuild cost. Neither is part of the app or of CI; run them by
hand when touching the search wiring or the game-screen hot path.

## `bench_search.dart` — fixed depth vs. a time budget

```sh
/mnt/volume1/toolchain/flutter/bin/dart run tool/perf/bench_search.dart
```

Walks a real game and searches each position at a fixed depth, then under a
1-second budget. It shows why fixed-depth play degrades: the same depth costs an
order of magnitude more once the position opens up, while a time budget simply
returns a shallower depth and keeps latency flat.

Measured on this machine (desktop x86, native):

```
ply | pieces |    d4 ms |    d6 ms |    d8 ms | depth reached in 1000ms
  0 |     32 |      196 |      471 |      692 | 8
  8 |     32 |       41 |      548 |     5144 | 6
 24 |     30 |       77 |      302 |     4647 | 6
 36 |     28 |       64 |      740 |     4877 | 6
 44 |     27 |       28 |      254 |     1596 | 7
```

## `bench_rebuild.dart` — cost of one game-screen rebuild

```sh
/mnt/volume1/toolchain/flutter/bin/flutter test tool/perf/bench_rebuild.dart
```

Times what the screen reads from `build()` — the SAN move list and the game-over
state — against the previous implementations, which re-derived both by replaying
the whole game on every call.

```
plies |  old us | new us | speedup
    4 |    1013 |      7 | 145x
   24 |    2219 |     14 | 159x
   46 |    3949 |     25 | 158x
```

## `tournament.dart` — engine vs engine

```sh
LD_LIBRARY_PATH=$PWD/linux \
  /mnt/volume1/toolchain/flutter/bin/flutter test tool/perf/tournament.dart
```

Round robin between every engine that can actually run on the machine, both
colours, from a small opening book so repeated pairings differ. Everyone gets
the same per-move budget, which makes the score a strength comparison and the
latency table a check that the budget is honoured.

Only native engines can take part — the WASM ones (Lynx WASM, web Stockfish,
Frozenight WASM, Lc0 web) need a browser. Frozenight needs
`native/frozenight/build.sh` to have been run; Lynx downloads its binary on
first use. A `stockfish` or `lc0` already on `PATH` joins as a reference
opponent; the harness never installs one.

56 games at 300 ms/move on this machine — every engine the app ships, including
the four that used to be browser-only (see `tool/uci/`):

```
=== Strength (300ms/move) ===
engine               | games |  W  D  L | score | vs field
Frozenight           |    12 |  9  2  1 |  10.0 |   +280
Lynx                 |    12 |  7  4  1 |   9.0 |   +191
Frozenight WASM      |    12 |  8  2  2 |   9.0 |   +191
Stockfish.js         |    12 |  7  2  3 |   8.0 |   +120
Built-in             |    12 |  3  0  9 |   3.0 |   -191
Maia3 Dart           |    12 |  2  0 10 |   2.0 |   -280
Lc0 (Maia 1900)      |    12 |  1  0 11 |   1.0 |   -417
Lynx WASM            |     0 |  0  0  0 |   0.0 |      —

=== Move latency (budget 300ms) ===
engine               | moves | median | p95  | max   | opening | late | late/opening
Frozenight           |   536 |    157 |  372 |   832 |     162 |  151 |         0.93
Lynx                 |   640 |    252 |  258 |   323 |     253 |  252 |         0.99
Frozenight WASM      |   569 |    168 |  356 |   721 |     174 |  164 |         0.95
Stockfish.js         |   625 |    314 |  333 |   379 |     320 |  312 |         0.98
Built-in             |   525 |    310 |  324 |   349 |     308 |  311 |         1.01
Maia3 Dart           |   462 |    576 |  806 |  1745 |     591 |  572 |         0.97
Lc0 (Maia 1900)      |   329 |     70 |  128 |   337 |      75 |   67 |         0.90
Lynx WASM            |    34 |    568 | 1095 |  1227 |     541 |  727 |         1.34

Lynx WASM: no move within 40s at ply 73
```

`late/opening` is the number to watch: the median move time after ply 40 divided
by the median before ply 20. A fixed-depth engine climbs here as the position
opens up; everything that finishes its games sits at ~1.

Three entries need reading with context:

- **Maia3 Dart** and **Lc0** answer from a single network forward pass, not a
  search, so the time budget does not apply to them — their latency columns are
  inference cost. Both imitate human play, so losing to real engines at equal
  time is the expected result rather than a defect.
- **Lynx WASM** overshoots its time budget, and one search here ran past 40 s,
  which ends its games. Note the conditions: eight engines playing at once on a
  loaded shared box, so that number is as likely to be CPU starvation as
  anything in the engine. Lynx's own overshoot is real but smaller, and a patch
  that tightens it roughly twofold is in `tool/patches/` awaiting a bundle
  rebuild. See `tool/uci/README.md`.
