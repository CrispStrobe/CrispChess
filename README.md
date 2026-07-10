# CrispChess

A cross-platform chess app and analysis workbench with pluggable engine backends. Play against AI opponents, analyze games with multiple engines, run engine tournaments, solve puzzles, explore openings, and train — all under permissive licensing.

Built with Flutter. Runs on Android, iOS, macOS, Linux, Windows, and Web (WASM).

**Live demo:** [crispchess.vercel.app](https://crispchess.vercel.app)

## Engines

CrispChess uses a plugin architecture that lets you swap between chess engines at runtime. You can also load **any UCI-compatible engine** from disk on desktop/mobile.

| Engine | License | ~ELO | Platforms | Notes |
|--------|---------|------|-----------|-------|
| **Built-in** | MIT | ~1800 | All | Pure Dart, alpha-beta + NMP + PVS |
| **Maia3 (JS)** | MIT (code) / AGPL-3.0 (weights)¹ | ~1500–2500 | Web | Neural net, human-like play via JS bridge |
| **Maia3 Dart** | MIT (code) / AGPL-3.0 (weights)¹ | ~1500–2500 | All | Neural net, pure Dart + ONNX Runtime |
| **Frozenight** | MIT / Apache-2.0 | ~3226 | All (WASM + FFI) | Rust NNUE engine |
| **Lynx** | MIT | ~3350 | All (WASM + native) | C# classical HCE, .NET WASM on web |
| **Stockfish** | GPL-3.0 | ~3200–3600 | All | Downloaded separately, never linked |
| **Lc0** | GPL-3.0 | ~1100–3300 | All | MCTS + neural net, downloaded separately |
| **Custom UCI** | Any | Any | Desktop/Mobile | Load any engine binary from disk |

- **Built-in** — pure Dart engine with alpha-beta pruning, null move pruning, principal variation search, transposition table, quiescence search with MVV-LVA + delta pruning, and piece-square table evaluation. Works everywhere including Web WASM.
- **Maia3** — ELO-conditioned neural network trained on human games. Three model sizes: 5M (~25MB), 23M (~92MB), 79M (~313MB). ¹ Weights are downloaded at runtime, never bundled — see [Engine Licenses](#engine-licenses) below for the full provenance chain and license status.
- **Frozenight** — NNUE-based Rust engine compiled to WASM for web.
- **Lynx** — strong classical engine (~3350 ELO) by Eduardo Caceres. MIT licensed. Runs as native binary (desktop, downloaded on first use) or .NET WASM in the browser (compiled from C# via `wasm-tools`, ~6 MB). Supports Chess960.
- **Stockfish** — strongest traditional engine. Runs as Web Worker (web), process (desktop/Android), or JavaScriptCore (iOS). Downloaded at runtime.
- **Lc0** — AlphaZero-style MCTS with Maia weights for human-like play.
- **Custom UCI** — load any UCI engine via the Engine Manager (desktop/mobile only). Auto-detects engine identity and options.

GPL-3.0 engines are never compiled into the app binary. They run as separate processes or are downloaded at runtime, keeping the app itself MIT-licensed.

## Features

### Play
- Play as White or Black against 7+ engines with hot-swapping
- Adjustable engine strength (0–20 skill levels, ~800–2400 ELO)
- Move hints with arrow overlay, undo/redo, abort
- Chess clock (12 presets + custom time controls with base + increment)
- Two-player local (pass and play)
- Premove support (queue move while engine thinks)
- Pondering (engine analyzes during your turn)
- 8 piece themes, 8 board color themes, animated moves, sound effects
- Blindfold mode (hide pieces, play by memory)
- Engine Hash and Threads configuration

### Chess Variants
- Chess960 / Fischer Random (game mode selector in settings)
- King of the Hill (win by king on center squares)
- Three-check (win by giving check 3 times, live counter display)

### Analysis Workbench
- **Load any UCI engine** from disk with auto-detected options
- **Multi-PV display** — top N engine lines with eval badges
- **Multi-engine analysis** — run 2+ engines side-by-side
- **Infinite analysis** (`go infinite`) on all engines
- **Game tree with variations** — branching move history, clickable navigation
- **Board annotations** — right-click drag for arrows, tap for colored squares
- **PV arrows** — best engine move shown as blue arrow on board
- **Position editor** — drag pieces, set castling/EP, FEN I/O
- **Syzygy tablebase** — 7-piece endgame lookup (all platforms including web)

### Opening Explorer
- Interactive board with move statistics from master games
- Win/draw/loss percentage bars for each candidate move
- Toggle between Masters and Online databases
- Navigate forward/back through opening lines
- Opening name and total games display

### Database & Export
- **PGN database browser** — load multi-game PGN, search/filter, statistics
- **PGN RAV export** — variations in parenthesized notation
- **Game history** — 500 games with star/favorites, result filtering, bulk export
- **Figurine algebraic notation** option (piece symbols instead of letters)
- Board screenshot capture
- PGN copy/paste with full variation support

### Engine vs Engine
- Match mode — two engines play N games with alternating colors
- Tournament mode — round-robin for 3+ engines with standings
- Live board display, configurable depth

### Training
- **Puzzles** — ~1600 tactical puzzles (CC0), rating-range filter
- **Puzzle Rush** — timed sprint (3 min), 3 lives, personal best tracking
- **Coordinate Trainer** — tap correct square, timed mode (30s), personal best
- **Drills** — 8 structured lessons (tactics, openings, endgames) with coach feedback
- **Endgame drills** — K+Q vs K, K+R vs K, K+P vs K, Two Bishops
- **Spaced repetition** — re-present failed positions at increasing intervals
- Post-game analysis with accuracy, eval chart, interactive board replay
- Per-move classification (brilliant/good/inaccuracy/mistake/blunder)
- Mistakes tracker with blunder review

### Gamification
- XP system with 6 level tiers (Pawn → Grandmaster)
- Level-up celebration dialog
- 12 achievement badges
- Daily login streak

### AI Coach (BYOK)
- Send position to Anthropic or OpenAI for natural language analysis
- Bring-your-own-key — stored locally, never transmitted to CrispChess servers
- Privacy-first design

## CLI

CrispChess includes a standalone command-line interface for engine analysis, puzzle solving, and engine matches — no Flutter or GUI required.

```bash
# Analyze a position
dart run bin/crispchess.dart analyze --engine stockfish --fen "starting" --depth 20

# Play interactively against an engine
dart run bin/crispchess.dart play --engine ~/.crispchess/engines/lynx/Lynx.Cli --depth 12

# Engine vs engine match
dart run bin/crispchess.dart match --white stockfish --black frozenight --games 10 --depth 15

# Performance test
dart run bin/crispchess.dart perft --depth 6

# Solve a puzzle
dart run bin/crispchess.dart puzzle --rating 1500

# Show board after moves
dart run bin/crispchess.dart fen e2e4 e7e5 g1f3 b8c6 f1c4
```

## Server API

A REST API server for programmatic access to chess analysis, puzzles, and board state.

```bash
dart run bin/server.dart --port 8080 --engine stockfish
```

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check |
| `GET /api/analyze?fen=...&depth=15` | Engine analysis (returns bestMove, eval, PV) |
| `GET /api/puzzle?rating=1500` | Random puzzle filtered by rating |
| `GET /api/puzzle/daily` | Deterministic daily puzzle |
| `GET /api/perft?depth=4` | Perft with node count and timing |
| `GET /api/board?fen=...` | Board state, legal moves, game status |
| `GET /api/fen?moves=e2e4,e7e5` | FEN resulting from a move sequence |

All endpoints return JSON with CORS enabled.

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel, Dart 3.5+)
- For Frozenight WASM: [Rust toolchain](https://rustup.rs/) + `wasm-pack`
- For Lynx WASM rebuild: [.NET 10 SDK](https://dotnet.microsoft.com/) + `wasm-tools` workload

### Build and Run

```bash
git clone https://github.com/CrispStrobe/CrispChess.git
cd CrispChess
flutter pub get
flutter run
```

The app works immediately with the built-in Dart engine. No native compilation needed.

### Build for Web (WASM)

```bash
flutter build web --release --wasm
```

### Build Frozenight WASM (optional)

```bash
cd native/frozenight-wasm
wasm-pack build --target web --release
cp pkg/frozenight_wasm.js ../../web/
cp pkg/frozenight_wasm_bg.wasm ../../web/
```

### Rebuild Lynx WASM (optional)

Pre-built WASM is committed in `web/lynx/`. Pre-built bundles are also available from [CrispStrobe/lynx-chess releases](https://github.com/CrispStrobe/lynx-chess/releases). To rebuild from source:

```bash
./scripts/build_lynx_wasm.sh
```

Requires .NET 10 SDK and `wasm-tools` workload. Clones from our [WASM-enabled Lynx fork](https://github.com/CrispStrobe/lynx-chess) (branch `wasm-browser`) which has all browser patches pre-applied, compiles to WASM, and copies the bundle to `web/lynx/`. See the fork's [WASM.md](https://github.com/CrispStrobe/lynx-chess/blob/wasm-browser/WASM.md) for details on the patches and JS interop API.

## Architecture

```
lib/
  engines/
    chess_engine.dart             # Abstract ChessEngine interface
    engine_factory.dart           # Engine creation with conditional imports
    generic_uci_engine.dart       # Load any UCI engine binary
    uci_option.dart               # UCI option model (spin/check/combo/etc.)
    dart_engine.dart              # Built-in Dart engine (MIT)
    lynx_engine.dart              # Lynx engine — native binary (desktop)
    lynx_web_engine.dart          # Lynx engine — .NET WASM (web)
    frozenight_engine.dart        # Frozenight FFI (native) / WASM (web)
    stockfish_engine.dart         # Stockfish process (native) / Web Worker
    maia3_dart_engine.dart        # Maia3 Dart — native ONNX
    lc0_engine.dart               # Lc0 MCTS + neural net
  services/
    engine_service.dart           # Engine lifecycle + event stream
    multi_engine_service.dart     # Multi-engine simultaneous analysis
    http_service.dart             # Cross-platform HTTP (dart:io / web fetch)
    preferences_service.dart      # Settings persistence
    sound_service.dart            # Sound effects (Web Audio / native)
  chess/
    chess_game.dart               # Game state + variant support
    game_tree.dart                # Branching move tree with variations
    board_theme.dart              # 8 board color themes
    notation.dart                 # Algebraic / figurine notation conversion
    variants.dart                 # KOTH and Three-check win conditions
    chess960.dart                 # Fischer Random position generator
    drill.dart                    # 8 structured drill lessons
    puzzle.dart                   # Puzzle database + rating filter
    tablebase.dart                # Syzygy endgame lookup (all platforms)
    opening_book.dart             # Opening database
    spaced_repetition.dart        # SR queue for mistake review
  screens/
    chess_game_screen.dart        # Main game UI
    settings_screen.dart          # Engine, strength, display settings
    opening_explorer_screen.dart  # Opening statistics explorer
    puzzle_screen.dart            # Puzzle mode + Puzzle Rush
    coordinate_trainer_screen.dart # Coordinate training
    game_history_screen.dart      # Browsable game history with favorites
    engine_match_screen.dart      # Engine vs engine matches/tournaments
    position_editor_screen.dart   # Board setup / FEN editor
    pgn_database_screen.dart      # PGN database browser
    drill_screen.dart             # Interactive drill player
    ai_coach_sheet.dart           # LLM analysis bottom sheet (BYOK)
    game_summary_screen.dart      # Post-game analysis
bin/
  crispchess.dart                 # CLI — analyze, play, match, perft, puzzle
  server.dart                     # REST API server
```

### Engine Interface

All engines implement `ChessEngine`:

```dart
abstract class ChessEngine {
  String get name;
  String get license;
  int get estimatedElo;
  EngineState get state;

  Future<void> initialize();
  Future<String> bestMove(String positionCommand, {int? depth, int? skillLevel});
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite});
  void setOption(String name, String value);
  void stop();
  void dispose();
}
```

Engines are hot-swappable at runtime via `EngineService.switchEngine()`.

## CI/CD

GitHub Actions on every push to `main`:

- **Analyze & Test** — Dart analyzer + 274 unit tests
- **Frozenight** — Compiles for WASM, Linux, macOS, iOS, Android arm64, Windows
- **Build** — Android APK, iOS, macOS, Linux, Web (WASM)
- **Deploy Web** — Builds Flutter WASM + Frozenight WASM, strips source maps, deploys to Vercel with caching headers

## License

**MIT** — see [LICENSE](LICENSE).

The app code, built-in Dart engine, Maia3 Dart port, Lynx integration, and all original code are MIT licensed.

### Engine Licenses

| Component | License | Bundled in binary |
|-----------|---------|-------------------|
| CrispChess app + Built-in engine | MIT | Yes |
| Maia3 Dart / JS (tokenization + sampling glue code) | MIT | Yes |
| Maia3 model weights | AGPL-3.0¹ | No — downloaded at runtime |
| Frozenight | MIT + Apache-2.0 | Yes (WASM) |
| Lynx | MIT | Yes (WASM on web), downloaded on desktop |
| ONNX Runtime Web | MIT | Yes (lazy-loaded JS) |
| Stockfish | GPL-3.0 | No — downloaded separately, runs isolated |
| Lc0 | GPL-3.0 | No — downloaded separately, runs isolated |

¹ **Maia3 weight provenance and license status.** CrispChess downloads
weights from `huggingface.co/cstr/maia3-onnx-int32` (a CrispChess-side
mirror, modified for Safari/WebKit ONNX compatibility, of
`cemoss17/maia3-onnx`). Both of those Hugging Face repos self-declare
MIT. However, the authoritative upstream source — the official
[CSSLab/maia3](https://github.com/CSSLab/maia3) repository by the
model's actual authors — is **AGPL-3.0**, and its own Hugging Face
model card (`MaiaChess/maia3-*`) explicitly states the weights follow
the repo's license, not an independent one. The downstream MIT
self-declarations on the repos this app actually pulls from do not
appear to carry a documented relicensing grant from CSSLab, so this
app treats the AGPL-3.0 status as authoritative going forward. Unlike
Stockfish/Lc0 — which are isolated in a separate OS process or Web
Worker (satisfying the standard "mere aggregation" exception) — Maia3
inference currently runs in-process via the `onnxruntime` plugin;
isolating it the same way is planned but not yet shipped. We intend to
reach out to CSSLab for clarification/permission; until resolved,
treat Maia3's licensing status as unsettled rather than assume the
downstream MIT tags are correct.

Piece themes are from [Lichess](https://github.com/lichess-org/lila) under MIT, CC0, or CC-BY 4.0.

## Contributing

Contributions welcome. Please open an issue first for major changes.
