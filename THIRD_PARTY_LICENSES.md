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

## Lc0

- **License:** GPL-3.0
- **Source:** https://github.com/LeelaChessZero/lc0

No lc0 code is bundled with, compiled into, or linked by CrispChess. There is
no lc0 WASM build to download either — the "Lc0" engine here is this app's own
Dart MCTS driving a Maia network through ONNX, on both web and native. The
network weights are downloaded at run time as data (see the weights entries
below).

One artefact is derived from the lc0 project and ships in the app:

- **The 112-plane input encoding** (`lib/engines/lc0_dart/encoding.dart`) —
  a Dart reimplementation of lc0's classical input format. Written from the
  format's description rather than copied, but it is a functional
  reimplementation of GPL-3.0 work. It is a data format rather than executable
  lc0 code, and it links nothing.

A transcription of lc0's `src/neural/tables/policy_map.h` used to ship as well,
in both `web/lc0_onnx_bridge.js` and a Dart copy. It is gone: the network
exports are now produced by lc0's own `leela2onnx`, whose policy head is already
in move-vocabulary order, so nothing needs remapping.

`lc0 leela2onnx` was used as a build-time tool to convert the weights. lc0 was
built from unmodified upstream source (v0.32.1), is not redistributed, and none
of its code is in the app. Running a GPL program over data does not place the
data under the GPL — the weights' license comes from their own authors (see the
weights entry below), not from the converter.

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
- **Two distinct acts, two different analyses — don't conflate them.**
  GPL/AGPL's obligations attach to *conveying* (distributing copies to
  others), not to mere *use*. Those are different acts here:

  1. **The HuggingFace re-upload — this is the actual "conveying" act.**
     `cemoss17/maia3-onnx` (converting CSSLab's original weights to
     ONNX) and, on top of that, our own `cstr/maia3-onnx-int32`
     (adding Cast nodes for Safari/WebKit) are both public re-uploads
     of a modified copy of AGPL-covered material — making copies
     available to anyone who visits those repos, independent of
     CrispChess's existence or behavior. Both self-declared **MIT**,
     but neither documents a relicensing grant from CSSLab — converting
     a model's file format doesn't, on its own, grant the right to
     relicense it under different terms. This is the step that needed
     fixing, and is fixed: `cstr/maia3-onnx-int32`'s license tag and
     README now correctly state AGPL-3.0 with attribution to the
     original source, rather than conveying it under an inaccurate
     permissive label.
  2. **The app's runtime download-and-use — a different, weaker case.**
     CrispChess fetching that file onto an end user's own device to run
     local inference is much closer to ordinary software use (`pip
     install` fetching a package, a browser fetching a resource) than
     to redistribution — no further copies are made available to
     anyone by the app itself. Whether trained weight *values* (as
     opposed to the code that produced them) carry a training
     project's copyleft into every downstream device that merely uses
     them is an unsettled question industry-wide, not specific to this
     app — the same one every project shipping downloaded
     GGUF/ONNX/safetensors weights derived from a copyleft-licensed
     training project operates under. The position here follows that
     norm: disclose the actual license accurately (this file, the
     README, and the in-app About screen all correctly state AGPL-3.0)
     and attribute properly, rather than seek case-by-case permission
     or assume undocumented relicensing.
- **Mitigation: no third-party code executes at all, on any platform.**
  Maia3 inference no longer uses Microsoft's `onnxruntime` (or any
  other pre-built ONNX runtime, JS or native). It runs on a from-scratch
  Dart interpreter (`lib/engines/maia3_dart/onnx/`) that parses the
  `.onnx` file's protobuf container (implementing the public,
  Apache-2.0 ONNX format specification — not CSSLab's code) and
  executes its computation graph using original Dart implementations
  of the ~25 standard ONNX operators (Add, MatMul, LayerNormalization,
  Softmax, etc. — all part of the open ONNX operator spec at onnx.ai).
  This is a strictly stronger position than the "isolated in a
  separate process/Worker" mitigation used for Stockfish/Lc0 below:
  there, GPL code still *executes*, just outside the app's own
  process. Here, no AGPL/GPL code executes anywhere, in any process —
  only original MIT code operating on downloaded numeric data. This
  change affects only act 2 above (the app's runtime download-and-use);
  act 1 (the HuggingFace re-upload) and its compliance status are
  unrelated to what executes the weights afterward.
- Verified numerically equivalent to the original `onnxruntime`-based
  implementation on the 5M model (max logit diff ~2e-5, matching
  float32 rounding) before switching over.
- **Previous note in this file** ("Research use... weights treated as
  independent output, same principle as GCC-compiled programs") is
  **retracted** — that reasoning doesn't hold once the actual rights
  holder has explicitly stated the weights follow the AGPL repo
  license; the GCC-output exception is an explicit carve-out the FSF
  wrote into GCC's own licensing, and no equivalent exception exists
  here.

## Maia/Lc0 Neural Network Weights

- **License: GPL-3.0-or-later.** Resolved 2026-09-03; this entry previously
  said "stated as Research use ... not independently re-verified". It has now
  been checked at the source: https://github.com/CSSLab/maia-chess ships a
  GPL-3.0 `LICENSE` and its README states "The software is available under the
  GPL License". Converting the weights to ONNX does not relicense them.
- **Source:** https://huggingface.co/cstr/maia-chess-onnx-opset15 —
  `maia-<elo>.onnx`, exported from the CSSLab `.pb.gz` weights with
  `lc0 leela2onnx` (v0.32.1). That repo's README carries the GPL-3.0-or-later
  notice and the conversion provenance, which is what redistributing them
  requires.
- **Original:** https://github.com/CSSLab/maia-chess

The app's own position is the same as it is for Stockfish: the weights are
downloaded at run time as data, on the user's request. Nothing GPL is bundled
in the app binary, nothing is linked, and the app redistributes nothing.

The earlier `maia-<elo>-opset15.onnx` files in that repo are mis-converted and
are no longer used — see the repo README. They are unrelated to licensing.

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

## Lc0 oracle test data

`tool/oracle/` checks this app's Lc0 implementation against lc0 itself. It
fetches, at run time and only in CI:

- the move vocabulary from
  [lczero-training](https://github.com/LeelaChessZero/lczero-training)
  (`tf/policy_index.py`, GPL-3.0), used as the reference the vendored copy in
  `lib/engines/lc0_dart/policy_map.dart` is compared against;
- [lc0](https://github.com/LeelaChessZero/lc0) v0.32.1 (GPL-3.0), built from
  source and run as a separate process;
- the original Maia weights from
  [CSSLab/maia-chess](https://github.com/CSSLab/maia-chess) (GPL-3.0).

None of it is redistributed with the app, and none is linked into it.
`tool/oracle/reference_encoder.py` is a transcription of the classical branch
of lc0's `src/neural/encoder.cc` and is therefore GPL-3.0; it is a test fixture
and ships in no build.
