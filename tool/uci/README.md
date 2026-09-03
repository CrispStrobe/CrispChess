# Headless UCI adapters

The browser-only engines wrapped as ordinary UCI processes, so the *same* build
the web app uses can be driven from a terminal, a script, or anything that
speaks UCI — including this repo's `GenericUciEngine` and the tournament
harness in `tool/perf/`.

The Dart classes for these engines talk to the browser through
`dart:js_interop` and cannot run outside one. The engines themselves are just
WASM/JS and run fine under Node, so the adapter is a thin stdin/stdout shim
rather than a reimplementation.

Each adapter is executable, so it can be used anywhere an engine path is
expected:

```sh
./tool/uci/lynx_wasm_uci.mjs
./tool/uci/stockfish_js_uci.mjs [sf10|sf18asm]
```

## `lynx_wasm_uci.mjs`

Lynx compiled to .NET WASM. Needs the build in `web/lynx/_framework`
(`scripts/build_lynx_wasm.sh`).

The Mono search runs to completion in one call, so commands are handled one at a
time and a `stop` sent mid-search takes effect when that search ends — the same
behaviour the browser build has.

Two things about this build are worth knowing before you trust its numbers.

**It has to warm up.** Mono tiers up as it runs, and the first search of a
session is not slightly slower, it is a different engine: measured here, cold it
reaches depth 1 (57 nodes) in a second, while after a single throwaway search on
an *unrelated* position it reaches depth 8 (10,574 nodes) in the same second.
Both this adapter and `lynx_web_engine.dart` now spend one short search up front
so the first real move is not the weak one.

**It does not reliably honour `movetime`.** Even warmed it runs on the order of
10k nodes/s, and the tournament saw a median of 608 ms against a 300 ms budget
with one search running past 40 s.

This is not a build problem, though it looked like one at first: the bundle was
rebuilt from source with .NET 10 and the `wasm-tools` workload (AOT), and it
performs the same as the artifact it replaced — so both are AOT and the speed is
simply what Lynx does under WASM. Repeated fixed-depth timings on a loaded
machine varied by 2x in *both* directions, so no speedup figure is quoted here.
Driving it with `go depth` instead does not help either; a fixed depth is what
made it slow in the first place. Treat its time budget as advisory.

## `stockfish_js_uci.mjs`

stockfish.js, downloaded on first run to `~/.crispchess/engines/stockfish-js/`
— the same "fetch at run time, never bundle" arrangement the app uses for this
GPL-3.0 engine.

It is packaged as a Web Worker: it assigns a bare `onmessage`, calls
`postMessage`, and reads `location.href` to find itself. Node's `worker_threads`
provides none of those, which is why loading it directly produces silence.
`_web_worker_shim.cjs` supplies the four globals it needs and then loads it.

## `frozenight_wasm_uci.mjs`

Frozenight compiled to WASM with wasm-bindgen. Build it first:

```sh
cd native/frozenight-wasm
cargo build --release --target wasm32-unknown-unknown
wasm-bindgen target/wasm32-unknown-unknown/release/frozenight_wasm.wasm   --out-dir ../../web --target web
```

There was no build artifact in `web/` at all before, so the browser build of
this engine could never have loaded — `frozenight_bridge.js` imports a
`frozenight_wasm.js` that did not exist.

The adapter does its own iterative deepening, checking the clock *before*
starting each depth: `search(d)` is a single uninterruptible WASM call, so
checking afterwards puts no bound on the iteration that overshoots.

## Engines with no headless path

- **Stockfish (desktop native)** — needs a `stockfish` binary on `PATH`; the
  tournament harness picks one up if present but never installs one. The same
  engine family is covered headlessly by `stockfish_js_uci.mjs`.
- **Stockfish (iOS)** — runs stockfish.js inside WebKit, which is a platform
  host rather than an engine of its own; `stockfish_js_uci.mjs` runs the very
  same JS.

Everything else the app ships — Built-in, Lynx (native and WASM), Frozenight
(FFI and WASM), Maia3 Dart, Lc0 — runs from the command line.
