# CrispChess

A cross-platform chess app and analysis workbench with pluggable engine backends. Play against AI opponents, analyze games with multiple engines, run engine tournaments, solve drills, and explore PGN databases — all under permissive licensing.

Built with Flutter. Runs on Android, iOS, macOS, Linux, Windows, and Web (WASM).

**Live demo:** [crispchess.vercel.app](https://crispchess.vercel.app)

## Engines

CrispChess uses a plugin architecture that lets you swap between chess engines at runtime. You can also load **any UCI-compatible engine** from disk on desktop/mobile.

| Engine | License | ~ELO | Platforms | Notes |
|--------|---------|------|-----------|-------|
| **Built-in** | MIT | ~1800 | All | Pure Dart, alpha-beta + NMP + PVS |
| **Maia3 (JS)** | MIT | ~1500–2500 | Web | Neural net, human-like play via JS bridge |
| **Maia3 Dart** | MIT | ~1500–2500 | All | Neural net, pure Dart + ONNX Runtime |
| **Frozenight** | MIT / Apache-2.0 | ~3226 | Web (WASM) | Rust NNUE engine |
| **Stockfish** | GPL-3.0 | ~3200–3600 | All | Downloaded separately, never linked |
| **Lc0** | GPL-3.0 | ~1100–3300 | All | MCTS + neural net, downloaded separately |
| **Custom UCI** | Any | Any | Desktop/Mobile | Load any engine binary from disk |

- **Built-in** — pure Dart engine with alpha-beta pruning, null move pruning, principal variation search, transposition table, quiescence search with MVV-LVA + delta pruning, and piece-square table evaluation. Works everywhere including Web WASM.
- **Maia3** — ELO-conditioned neural network trained on human games. Three model sizes: 5M (~25MB), 23M (~92MB), 79M (~313MB).
- **Frozenight** — NNUE-based Rust engine compiled to WASM for web.
- **Stockfish** — strongest traditional engine. Runs as Web Worker (web), process (desktop/Android), or JavaScriptCore (iOS). Downloaded at runtime.
- **Lc0** — AlphaZero-style MCTS with Maia weights for human-like play.
- **Custom UCI** — load any UCI engine via the Engine Manager (desktop/mobile only). Auto-detects engine identity and options.

GPL-3.0 engines are never compiled into the app binary. They run as separate processes or are downloaded at runtime, keeping the app itself MIT-licensed.

## Features

### Play
- Play as White or Black against 6+ engines with hot-swapping
- Adjustable engine strength (0–20 skill levels, ~800–2400 ELO)
- Move hints with arrow overlay, undo/redo, abort
- Chess clock (12 presets: bullet to classical)
- Two-player local (pass and play)
- Premove support (queue move while engine thinks)
- Pondering (engine analyzes during your turn)
- 8 piece themes, animated moves, sound effects

### Analysis Workbench
- **Load any UCI engine** from disk with auto-detected options
- **Multi-PV display** — top N engine lines with eval badges
- **Multi-engine analysis** — run 2+ engines side-by-side
- **Infinite analysis** (`go infinite`) on all engines
- **Game tree with variations** — branching move history, clickable navigation
- **Board annotations** — right-click drag for arrows, tap for colored squares
- **PV arrows** — best engine move shown as blue arrow on board
- **Position editor** — drag pieces, set castling/EP, FEN I/O
- **FEN input** — paste any position

### Database & Export
- **PGN database browser** — load multi-game PGN, search/filter, statistics
- **PGN RAV export** — variations in parenthesized notation
- Board screenshot capture
- PGN copy/paste with full variation support

### Engine vs Engine
- Match mode — two engines play N games with alternating colors
- Tournament mode — round-robin for 3+ engines with standings
- Live board display, configurable depth

### Training
- **Puzzles** — 200 tactical puzzles from Lichess (CC0)
- **Drills** — structured lessons (tactics, openings, endgames) with coach feedback
- **Spaced repetition** — re-present failed positions at increasing intervals
- Post-game analysis with accuracy, eval chart, interactive board replay
- Per-move classification (brilliant/good/inaccuracy/mistake/blunder)
- Mistakes tracker with blunder review

### Gamification
- XP system with 6 level tiers (Pawn → Grandmaster)
- Level-up celebration dialog
- 12 achievement badges
- Daily login streak

### Chess Variants
- Chess960 / Fischer Random
- King of the Hill (win by king on center squares)
- Three-check (win by giving check 3 times)

### AI Coach (BYOK)
- Send position to Anthropic or OpenAI for natural language analysis
- Bring-your-own-key — stored locally, never transmitted to CrispChess servers
- Privacy-first design

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel, Dart 3.5+)
- For Frozenight WASM: [Rust toolchain](https://rustup.rs/) + `wasm-pack`

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

## Architecture

```
lib/
  engines/
    chess_engine.dart             # Abstract ChessEngine interface
    engine_factory.dart           # Engine creation with conditional imports
    generic_uci_engine.dart       # Load any UCI engine binary
    uci_option.dart               # UCI option model (spin/check/combo/etc.)
    uci_position.dart             # UCI position command → FEN parser
    dart_engine.dart              # Built-in Dart engine (MIT)
    dart_engine/
      evaluation.dart             # Piece-square tables, material eval
      search.dart                 # Alpha-beta, NMP, PVS, quiescence, TT
      transposition.dart          # Transposition table
    maia3_dart_engine.dart        # Maia3 Dart — native ONNX
    maia3_dart_web_engine.dart    # Maia3 Dart — web ONNX bridge
    frozenight_web_engine.dart    # Frozenight WASM (web)
    frozenight_engine.dart        # Frozenight FFI (native)
    stockfish_web_engine.dart     # Stockfish Web Worker (web)
    stockfish_engine.dart         # Stockfish process (native)
    lc0_web_engine.dart           # Lc0 web (ONNX)
    lc0_engine.dart               # Lc0 native
  services/
    engine_service.dart           # Engine lifecycle + event stream
    multi_engine_service.dart     # Multi-engine simultaneous analysis
    engine_match_service.dart     # Engine vs engine matches + tournaments
    engine_profile_store.dart     # Custom engine profile persistence
    preferences_service.dart      # Settings persistence
    sound_service.dart            # Web Audio API synthesis
  chess/
    chess_game.dart               # Game state + variant support
    game_state.dart               # Immutable UI state with copyWith
    game_tree.dart                # Branching move tree with variations
    board_annotations.dart        # Arrows and colored squares model
    variants.dart                 # KOTH and Three-check win conditions
    drill.dart                    # Structured drill lesson system
    spaced_repetition.dart        # SR queue for mistake re-presentation
    pgn.dart                      # PGN export/import with RAV variations
    pgn_database.dart             # Multi-game PGN parser + search
    move_analyzer.dart            # Move quality classification
    opening_book.dart             # Opening database
    xp_system.dart                # XP and player levels
  screens/
    chess_game_screen.dart        # Main game UI
    settings_screen.dart          # Engine, strength, display settings
    engine_manager_screen.dart    # Custom UCI engine management
    engine_match_screen.dart      # Engine vs engine matches/tournaments
    position_editor_screen.dart   # Board setup / FEN editor
    pgn_database_screen.dart      # PGN database browser
    drill_screen.dart             # Interactive drill player
    ai_coach_sheet.dart           # LLM analysis bottom sheet (BYOK)
    game_summary_screen.dart      # Post-game analysis with interactive board
    puzzle_screen.dart            # Puzzle mode
    stats_screen.dart             # Player statistics
  widgets/
    chess_board.dart              # Board with animation + annotations
    board_annotation_overlay.dart # Arrow/highlight custom painter
    capture_effect.dart           # Particle burst on captures
    press_scale.dart              # Press-down scale animation wrapper
    eval_chart.dart               # Evaluation history chart
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
  void stop();
  void dispose();
}
```

Engines are hot-swappable at runtime via `EngineService.switchEngine()`.

## CI/CD

GitHub Actions on every push to `main`:

- **Analyze & Test** — Dart analyzer + unit tests
- **Frozenight** — Compiles for WASM, Linux, macOS, iOS, Android arm64, Windows
- **Build** — Android APK, iOS, macOS, Linux, Web (WASM)
- **Deploy Web** — Builds Flutter WASM + Frozenight WASM, strips source maps, deploys to Vercel with caching headers

## License

**MIT** — see [LICENSE](LICENSE).

The app code, built-in Dart engine, Maia3 Dart port, and all original code are MIT licensed.

### Engine Licenses

| Component | License | Bundled in binary |
|-----------|---------|-------------------|
| CrispChess app + Built-in engine | MIT | Yes |
| Maia3 Dart (tokenization + sampling) | MIT | Yes |
| ONNX model weights (maia3-onnx) | Research use | Downloaded at runtime |
| Frozenight | MIT + Apache-2.0 | Yes (WASM) |
| ONNX Runtime Web | MIT | Yes (lazy-loaded JS) |
| Stockfish | GPL-3.0 | No — downloaded separately |
| Lc0 | GPL-3.0 | No — downloaded separately |

Piece themes are from [Lichess](https://github.com/lichess-org/lila) under MIT, CC0, or CC-BY 4.0.

## Contributing

Contributions welcome. Please open an issue first for major changes.
