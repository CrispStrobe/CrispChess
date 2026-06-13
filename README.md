# CrispChess

A cross-platform chess app with pluggable engine backends. Play against AI opponents ranging from beginner-friendly to grandmaster-level — all under permissive licensing.

Built with Flutter. Runs on Android, iOS, macOS, Linux, Windows, and Web (WASM).

**Live demo:** [crispchess.vercel.app](https://crispchess.vercel.app)

## Engines

CrispChess uses a plugin architecture that lets you swap between chess engines at runtime via the settings screen.

| Engine | License | ~ELO | Platforms | Notes |
|--------|---------|------|-----------|-------|
| **Built-in** | MIT | ~1800 | All | Pure Dart, alpha-beta + TT |
| **Maia3 (JS)** | MIT | ~1500–2500 | Web | Neural net, human-like play via JS bridge |
| **Maia3 Dart** | MIT | ~1500–2500 | All | Neural net, pure Dart + ONNX Runtime |
| **Frozenight** | MIT / Apache-2.0 | ~3226 | Web (WASM) | Rust NNUE engine |
| **Stockfish** | GPL-3.0 | ~3200–3600 | All | Downloaded separately, never linked |
| **Lc0** | GPL-3.0 | ~1100–3300 | Mobile/Desktop | MCTS + neural net, downloaded separately |

- **Built-in** — pure Dart engine with alpha-beta pruning, transposition table, quiescence search, and piece-square table evaluation. Works everywhere including Web WASM. No native dependencies.
- **Maia3** — ELO-conditioned neural network trained on human games. Plays like a real human at the specified rating. Three model sizes: 5M (~25MB, ~1800 ELO), 23M (~92MB, ~2200 ELO), 79M (~313MB, ~2500 ELO). Selectable in settings. The Dart version ports all tokenization/sampling to Dart with platform-specific ONNX inference.
- **Frozenight** — NNUE-based Rust engine compiled to WASM for web. Stronger than any human.
- **Stockfish** — strongest traditional engine. Runs as a Web Worker (web), via JavaScriptCore (iOS), or as a separate process (desktop/Android). Downloaded at runtime — app binary stays MIT.
- **Lc0 (Leela Chess Zero)** — AlphaZero-style neural network engine with MCTS. Uses Maia weights for human-like play. Mobile/desktop only (no web build available). Downloaded separately.

GPL-3.0 engines (Stockfish, Lc0) are never compiled into the app binary. They run as separate processes or are downloaded at runtime, keeping the app itself MIT-licensed.

## Features

- Play as White or Black (configurable)
- 6 selectable chess engines with hot-swapping
- Maia3 model variant selection (5M / 23M / 79M)
- Adjustable engine strength (0–20 skill levels, ~800–2400 ELO)
- Move hints (engine suggests your best move)
- Live position evaluation
- Animated piece movement
- Drag-and-drop and tap-to-move interaction
- Legal move highlighting
- Move history display
- Undo support
- Abort button to cancel engine thinking
- Engine status indicator (loading / ready / thinking)
- 8 piece themes (Chessnut, Rhosgfx, Fantasy, Spatial, Celtic, Kiwen Suwi, Totoy, Papercut)
- SVG piece rendering
- Responsive layout (desktop + mobile)
- About screen with license info, version, and git hash

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

### Build Frozenight Native (optional)

```bash
cd native/frozenight
cargo build --release
# Copy the library to your platform's expected location
```

## Architecture

```
lib/
  engines/
    chess_engine.dart             # Abstract ChessEngine interface
    engine_factory.dart           # Engine creation with conditional imports
    uci_position.dart             # UCI position command → FEN parser
    dart_engine.dart              # Built-in Dart engine (MIT)
    dart_engine/
      evaluation.dart             # Piece-square tables, material eval
      search.dart                 # Alpha-beta, quiescence search, TT
      transposition.dart          # Transposition table
    maia3_web_engine.dart         # Maia3 via JS bridge (web)
    maia3_engine.dart             # Maia3 native stub
    maia3_dart_engine.dart        # Maia3 Dart — native ONNX
    maia3_dart_web_engine.dart    # Maia3 Dart — web ONNX bridge
    maia3_dart/
      encoding.dart               # Board tokenization (64×96 tensor)
      moves.dart                  # Move vocabulary (4352 UCI strings)
      utils.dart                  # Softmax, sampling, WDL
      history.dart                # FEN history resolution
      variants.dart               # Model variant registry (5m/23m/79m)
      onnx_model.dart             # Abstract ONNX model interface
      onnx_model_native.dart      # Native ONNX via onnxruntime package
      onnx_model_web.dart         # Web ONNX via JS bridge
    frozenight_web_engine.dart    # Frozenight WASM (web)
    frozenight_engine.dart        # Frozenight FFI (native)
    stockfish_web_engine.dart     # Stockfish Web Worker (web)
    stockfish_engine.dart         # Stockfish process (native)
    lc0_engine.dart               # Leela Chess Zero stub
  services/
    engine_service.dart           # Engine lifecycle + event stream
  chess/
    chess_game.dart               # Game state (ChangeNotifier)
    game_state.dart               # Immutable UI state with copyWith
  screens/
    chess_game_screen.dart        # Main game UI
    settings_screen.dart          # Engine, strength, display settings
    about_screen.dart             # License info, version, privacy
  widgets/
    chess_board.dart              # Board with animation + drag/drop

web/
  frozenight_bridge.js            # Frozenight WASM ↔ Dart bridge
  maia3_bridge.js                 # Maia3-js ↔ Dart bridge
  maia3_onnx_bridge.js            # Raw ONNX inference bridge for Maia3 Dart
  maia3-bundle.js                 # Bundled maia3-js (esbuild)
  ort.min.js                      # ONNX Runtime Web (bundled)
  stockfish.js                    # Stockfish Web Worker

native/
  frozenight-wasm/                # Rust → WASM (wasm-pack)
  frozenight/                     # Rust → native FFI (cdylib)
```

### Engine Interface

All engines implement `ChessEngine`:

```dart
abstract class ChessEngine {
  String get name;
  String get license;
  int get estimatedElo;
  EngineState get state;
  ValueNotifier<EngineState> get stateNotifier;

  Future<void> initialize();
  Future<String> bestMove(String positionCommand, {int? depth, int? skillLevel});
  Stream<EvalInfo> analyze(String positionCommand, {int? depth});
  void stop();
  void dispose();
}
```

Engines are hot-swappable at runtime via `EngineService.switchEngine()`.

Platform-specific code uses Dart conditional imports:
```dart
import 'frozenight_engine.dart'
    if (dart.library.js_interop) 'frozenight_web_engine.dart';
```

## CI/CD

GitHub Actions on every push to `main`:

- **Analyze & Test** — Dart analyzer + unit tests
- **Frozenight** — Compiles for WASM, Linux, macOS, iOS, Android arm64
- **Build** — Android APK, iOS, macOS, Linux, Web (WASM)
- **Deploy Web** — Builds Flutter WASM + Frozenight WASM, deploys to Vercel

## Testing

```bash
flutter test                      # Unit and widget tests
flutter test integration_test/    # Integration tests (needs device)
```

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
| ONNX Runtime Web | MIT | Yes (bundled JS) |
| Stockfish | GPL-3.0 | No — downloaded separately |
| Lc0 | GPL-3.0 | No — downloaded separately |

Piece themes are from [Lichess](https://github.com/lichess-org/lila) under MIT, CC0, or CC-BY 4.0.

### Dependencies

All Flutter/Dart dependencies use permissive licenses (BSD-2, BSD-3, MIT).

## Contributing

Contributions welcome. Please open an issue first for major changes.

## Roadmap

- [ ] Opening book integration
- [ ] Time controls
- [ ] PGN export/import
- [ ] Board flip animation
- [ ] Sound effects
- [ ] Frozenight native FFI on all platforms
- [ ] Lc0 web support (pending upstream WASM build)
- [ ] App Store / Play Store release
