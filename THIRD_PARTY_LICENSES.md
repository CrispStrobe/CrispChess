# Third-Party Licenses

This file documents third-party components distributed with CrispChess
that have licenses different from CrispChess's own MIT license.

## Stockfish (downloaded at runtime, NOT bundled)

- **License:** GPL-3.0
- **Author:** Niklas Fiekas (JS/WASM compilation)
- **Source:** https://github.com/niklasf/stockfish.js
- **Original authors:** T. Romstad, M. Costalba, J. Kiiski, G. Linscott et al.

Stockfish is NOT included in the CrispChess distribution. It is
downloaded from CDN (cdn.jsdelivr.net) at runtime when the user
selects it, and runs in a Web Worker (web) or separate process
(desktop). No GPL code is bundled with or compiled into CrispChess.

## Lynx Chess Engine (downloaded at runtime)

- **License:** MIT
- **Author:** Eduardo Caceres
- **Source:** https://github.com/lynx-chess/Lynx

Lynx is a C# chess engine (~3350 ELO). Self-contained binary
downloaded from GitHub Releases on first use. MIT licensed.

## Lc0 (downloaded at runtime, NOT bundled)

- **License:** GPL-3.0
- **Source:** https://github.com/LeelaChessZero/lc0

Lc0 WASM is downloaded at runtime. No GPL code is bundled with
or compiled into CrispChess.

## ONNX Runtime Web (web/ort.min.js)

- **License:** MIT
- **Source:** https://github.com/microsoft/onnxruntime

## Maia3 Neural Network Weights

- **License:** Research use (model weights are outputs, not code)
- **Source:** https://huggingface.co/cemoss17/maia3-onnx
- **Training code:** AGPL (CSSLab/maia-chess), but weights are treated
  as independent output (same principle as GCC-compiled programs).

## Maia/Lc0 Neural Network Weights

- **License:** Research use
- **Source:** https://huggingface.co/shermansiu/maia-1100 through maia-1900
- **Original:** https://github.com/CSSLab/maia-chess

## Piece Themes

All from Lichess (https://github.com/lichess-org/lila):
- chessnut: MIT
- fantasy: MIT
- spatial: MIT
- celtic: MIT
- rhosgfx: CC0
- kiwen-suwi: CC-BY 4.0
- totoy: CC-BY 4.0
- papercut: CC-BY 4.0
