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

## Lynx Chess Engine

- **License:** MIT
- **Author:** Eduardo Caceres
- **Source:** https://github.com/lynx-chess/Lynx
- **WASM fork:** https://github.com/CrispStrobe/lynx-chess (with browser patches)

Lynx is a C# chess engine (~3350 ELO). On desktop, a self-contained
binary is downloaded from GitHub Releases on first use. On web, Lynx
is compiled to WebAssembly via .NET `wasm-tools` and bundled in
`web/lynx/` (~6 MB). The WASM build includes patches for browser
compatibility (SocketsHttpHandler stub, Thread.Priority guard, warmup
skip, Convert.ToUInt64 overflow fix). MIT licensed.

## .NET Runtime (bundled in web/lynx/)

- **License:** MIT
- **Source:** https://github.com/dotnet/runtime
- **Component:** Mono WASM interpreter runtime

The .NET Mono runtime (`dotnet.native.wasm`, `dotnet.js`) is bundled
with the Lynx WASM build to execute the C# engine in the browser.
MIT licensed.

## Lc0 (downloaded at runtime, NOT bundled)

- **License:** GPL-3.0
- **Source:** https://github.com/LeelaChessZero/lc0

Lc0 WASM is downloaded at runtime. No GPL code is bundled with
or compiled into CrispChess.

## ONNX Runtime Web (web/ort.min.js)

- **License:** MIT
- **Source:** https://github.com/microsoft/onnxruntime

## Maia3 Neural Network Weights

- **Authoritative license: AGPL-3.0.** The official authors' repo,
  https://github.com/CSSLab/maia3, is AGPL-3.0, and its own Hugging
  Face model cards (`MaiaChess/maia3-*`) explicitly say the weights
  follow the repo's license ("see repo for code/weights license") —
  i.e. the copyright holders themselves say AGPL-3.0 covers the
  weights, not just the training code.
- **What we actually download:** `huggingface.co/cstr/maia3-onnx-int32`
  (a CrispChess-side mirror/modification of `cemoss17/maia3-onnx`,
  adding ONNX Cast nodes for Safari/WebKit compatibility). Both of
  those intermediate repos self-declare **MIT**, but neither documents
  a relicensing grant from CSSLab — converting a model's file format
  does not, on its own, grant the right to relicense it under
  different terms. We are treating the downstream MIT tags as
  unverified and the AGPL-3.0 upstream status as the one to actually
  comply with, pending a response from CSSLab.
- **Current mitigation status:** unlike Stockfish/Lc0 below, which are
  never bundled and run in an isolated process/Web Worker (the
  standard "mere aggregation" exception), Maia3 inference currently
  runs **in-process** via the `onnxruntime` Flutter plugin on all
  platforms. Isolating it into a separate process/Worker/WebView
  (matching Stockfish's treatment) is planned, not yet shipped — until
  then, treat this component's compliance status as open, not settled.
- **Previous note in this file** ("Research use... weights treated as
  independent output, same principle as GCC-compiled programs") is
  **retracted** — that reasoning doesn't hold once the actual rights
  holder has explicitly stated the weights follow the AGPL repo
  license; the GCC-output exception is an explicit carve-out the FSF
  wrote into GCC's own licensing, and no equivalent exception exists
  here.

## Maia/Lc0 Neural Network Weights

- **License:** stated as "Research use" on the Hugging Face repo, not
  independently re-verified against the original CSSLab/maia-chess
  license the way Maia3 was above — this entry should get the same
  level of scrutiny before being relied on. Flagged, not yet resolved.
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
