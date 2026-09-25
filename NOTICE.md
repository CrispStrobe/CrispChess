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

| Theme | Author | License |
|-------|--------|---------|
| Chessnut | [Alexis Luengas](https://github.com/LexLuengas/chessnut-pieces) | Apache-2.0 |
| Rhosgfx | [RhosGFX](https://rhosgfx.itch.io/) | CC0 1.0 |
| Fantasy | [Maurizio Monge](https://github.com/maurimo/chess-art) | MIT |
| Spatial | [Maurizio Monge](https://github.com/maurimo/chess-art) | MIT |
| Celtic | [Maurizio Monge](https://github.com/maurimo/chess-art) | MIT |
| Kiwen Suwi | [neverRare](https://github.com/neverRare) | CC BY 4.0 |
| Totoy | Kosal Sen | CC BY 4.0 |
| Papercut | [Nikolay Anzarov](https://nikoichu.itch.io/) | CC BY 4.0 |

Authors and licences as listed in Lichess's
[COPYING.md](https://github.com/lichess-org/lila/blob/master/COPYING.md).

## ChessMamba

The ChessMamba engine uses the model, weights and search design of
[ChessMamba](https://huggingface.co/TobiasLogic/chessmamba) by TobiasLogic
(MIT). Its ONNX export is downloaded at run time from
[cstr/chessmamba-onnx](https://huggingface.co/cstr/chessmamba-onnx); the
search is a Dart port of its `search.py`.

## Searchless transformers (DeepMind)

The "Searchless 9M / 136M / 270M" engines use the model weights of
[Grandmaster-Level Chess Without Search](https://github.com/google-deepmind/searchless_chess)
by Google DeepMind (Ruoss et al., 2024). The weights are licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and the original code
under Apache-2.0. **Changes:** the JAX checkpoints were converted to ONNX
(attention written as matrix products, same computation), and the 136M and
270M weights are stored in fp16. The converted files are downloaded at run
time from [cstr/searchless-chess-onnx](https://huggingface.co/cstr/searchless-chess-onnx);
the input encoding in `lib/engines/searchless/tokenizer.dart` follows the
original `tokenizer.py`.

## Language-model bot zoo

The "LM:" engines are small chess language models by their authors below,
converted to ONNX with a KV cache and downloaded at run time from
[cstr/chess-lm-zoo-onnx](https://huggingface.co/cstr/chess-lm-zoo-onnx). Each
keeps its licence; only MIT and Apache-2.0 models are included.

| Engine | Model | Author | Licence |
|---|---|---|---|
| LM: Chess Llama 68M | [bharathrajcl/chess_llama_68m](https://huggingface.co/bharathrajcl/chess_llama_68m) | bharathrajcl | Apache-2.0 |
| LM: ChessSLM-PM | [FlameF0X/ChessSLM-PM](https://huggingface.co/FlameF0X/ChessSLM-PM) | FlameF0X | Apache-2.0 |
| LM: AMD Chess | [nlpguy/amdchess-v9](https://huggingface.co/nlpguy/amdchess-v9) | nlpguy | Apache-2.0 |
| LM: GrandPythia | [mlabonne/grandpythia-200k-70m](https://huggingface.co/mlabonne/grandpythia-200k-70m) | Maxime Labonne | Apache-2.0 |
| LM: DialoChess | [DedeProGames/dialochess](https://huggingface.co/DedeProGames/dialochess) | DedeProGames | MIT |
| LM: SmolChess | [nlpguy/smolchess-v2](https://huggingface.co/nlpguy/smolchess-v2) | nlpguy | Apache-2.0 |
| LM: Chesser | [DedeProGames/Chesser-248K-Mini](https://huggingface.co/DedeProGames/Chesser-248K-Mini) | DedeProGames | Apache-2.0 |
| LM: Chessformer | [nsarrazin/chessformer](https://huggingface.co/nsarrazin/chessformer) | nsarrazin | MIT |

## Board-scanning model

`assets/models/board_squares.onnx` was trained for this app from scratch
(`tool/board_vision/`) and is MIT like the app. Its training images are
synthetic, rendered from permissively licensed sources only — no copyleft,
share-alike or non-commercial source, no photographs or third-party datasets:

| Source | Author | Licence |
|--------|--------|---------|
| the eight piece themes above | as above | as above |
| [Firi](https://github.com/jfaure/Firi-pieceset) pieces | James Faure | CC BY 4.0 |
| DejaVu Sans / Serif (chess glyphs, labels) | DejaVu fonts team, Bitstream | Bitstream Vera licence |
| [Noto Sans Symbols 2](https://github.com/notofonts/symbols) | The Noto Project Authors | SIL OFL 1.1 |
| [JuliaMono](https://github.com/cormullion/juliamono) | The JuliaMono Project Authors | SIL OFL 1.1 |
| [Fairfax HD](https://github.com/kreativekorp/open-relay) | Kreative Software | SIL OFL 1.1 |
| [GNU Unifont](https://unifoundry.com/unifont/) 15.1.05 | Roman Czyborra, Paul Hardy et al. | SIL OFL 1.1 (upstream dual licence; the OFL option is used) |

## Photo scanning (real boards)

Photo mode's board localisation and square crops are ports of
[chesscog](https://github.com/georg-wolflein/chesscog) (Georg Wölflein and
Ognjen Arandjelović, *J. Imaging* 2021; MIT). Its two classifiers
(MobileNetV3-Small, downloaded on first use from
[cstr/chess-board-photo-onnx](https://huggingface.co/cstr/chess-board-photo-onnx), initialised from
torchvision's ImageNet weights, BSD-3) were trained for this app on:

- chesscog's synthetic renders (OSF xf3ka), CC BY 4.0;
- [samryan18/chess-dataset](https://github.com/samryan18/chess-dataset),
  © 2019 Samuel Ryan, Mukund Venkateswaran, Kurt Convey, Michael Deng, MIT
  (also the two test photos in `test/fixtures/board_photo/`);
- Roboflow 100 "chess pieces" (`chess-pieces-mjzgj`), CC BY 4.0.

## Voice moves

Speech recognition by CrispASR (MIT, CrispStrobe) running OpenAI's Whisper
(MIT). The spoken move is matched against the legal moves of the position by
scoring each move's phrases, on the device; no audio leaves it.

## Chess puzzle data

Puzzles are from the [Lichess puzzle database](https://database.lichess.org/#puzzles) (CC0).

## ONNX model weights

Maia3 ONNX weights are from [CSSLab/maia-chess](https://github.com/CSSLab/maia-chess) and are provided for research use. They are downloaded at runtime, not bundled.

> The MIT `LICENSE` text is kept canonical so the license is machine-detectable;
> engine-licensing nuance lives here in `NOTICE.md`.
