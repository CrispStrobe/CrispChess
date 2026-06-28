# Licensing & Attribution

CrispChess is **MIT-licensed** (see [`LICENSE`](LICENSE)). That covers the app and
all first-party code including the built-in Dart engine, game tree, analysis
workbench, drill system, and all UI code.

## Pluggable engines

CrispChess can run different chess engines behind a common interface. Each engine
keeps its own license:

| Engine | License | Bundled | Notes |
|---|---|---|---|
| Built-in (Dart) | MIT | Yes | Pure Dart, no native deps |
| Maia3 Dart | MIT | Yes | Tokenization + sampling in Dart |
| Frozenight | MIT / Apache-2.0 | Yes (WASM) | Rust NNUE engine |
| ONNX Runtime Web | MIT | Yes | Lazy-loaded JS |
| **Stockfish** | **GPL-3.0** | No | Downloaded at runtime |
| **Lc0** | **GPL-3.0** | No | Downloaded at runtime |
| Custom UCI | Varies | No | User-provided binary |

**GPL-3.0 engines (Stockfish, Lc0) are never compiled into or bundled with the
app binary.** They are obtained and run at runtime:

- **Desktop/Android:** a separate Stockfish process (system binary / extracted).
- **iOS:** `stockfish.js` is downloaded from a CDN and run inside **WebKit**
  (`StockfishJSBridge.swift`). The app binary contains no GPL code; this is the
  App Store-sanctioned path (Guideline 2.5.2 / DPLA §3.3.2 — code executed by
  WebKit/JavaScriptCore that doesn't change the app's primary purpose).
- **Web:** `stockfish.js` is downloaded from a CDN and run in a Web Worker.

This keeps the distributed app MIT-licensed (the GPL engine is never linked in).

Custom UCI engines loaded via the Engine Manager are user-provided binaries
and their licensing is the user's responsibility.

## Piece themes

Piece SVG themes are from [Lichess](https://github.com/lichess-org/lila):

| Theme | License |
|-------|---------|
| Chessnut | MIT |
| Rhosgfx | CC0 |
| Fantasy | MIT |
| Spatial | MIT |
| Celtic | MIT |
| Kiwen Suwi | CC-BY 4.0 |
| Totoy | CC-BY 4.0 |
| Papercut | CC-BY 4.0 |

## Chess puzzle data

Puzzles are from the [Lichess puzzle database](https://database.lichess.org/#puzzles) (CC0).

## ONNX model weights

Maia3 ONNX weights are from [CSSLab/maia-chess](https://github.com/CSSLab/maia-chess) and are provided for research use. They are downloaded at runtime, not bundled.

> The MIT `LICENSE` text is kept canonical so the license is machine-detectable;
> engine-licensing nuance lives here in `NOTICE.md`.
