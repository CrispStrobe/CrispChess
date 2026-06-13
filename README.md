# CrispChess

A cross-platform chess app with pluggable engine backends. Play against AI opponents ranging from beginner-friendly to grandmaster-crushing — all under permissive licensing.

Built with Flutter. Runs on Android, iOS, macOS, Linux, Windows, and Web.

## Engines

CrispChess uses a plugin architecture that lets you swap between different chess engines at runtime.

| Engine | License | ~ELO | Bundled | Platforms |
|--------|---------|------|---------|-----------|
| **CrispEngine** | MIT | 1800 | Yes | All (incl. Web WASM) |
| **Frozenight** | MIT / Apache-2.0 | 2960 | Via CI | Linux, macOS, iOS, Android, Windows |
| **Stockfish** | GPL-3.0 | 3600 | Downloaded | All (incl. iOS via JavaScriptCore) |
| **Lc0 (Leela)** | GPL-3.0 | 1100-3300 | Optional | iOS, Android (via package) |

- **CrispEngine** — built-in pure Dart engine. Alpha-beta + transposition table + WASM on web. No native deps.
- **Frozenight** — NNUE-based Rust engine (MIT). Compiled in CI for all native platforms. Stronger than any human.
- **Stockfish** — strongest engine. Downloaded at runtime, not linked into app binary. Runs via Web Worker (web), JavaScriptCore (iOS), or separate process (desktop). App stays MIT.
- **Lc0 (Leela Chess Zero)** — neural network engine with human-like play. Uses Maia weights trained on real human games. Optional `leela_chess_zero` package.

## Features

- Play as White against the engine
- Move hints (engine suggests your best move)
- Live position evaluation with depth indicator
- Move analysis with tactical pattern detection (forks, pins, material gain)
- Move quality annotations (brilliant, good, dubious, blunder)
- Adjustable engine strength (0–20 skill levels)
- Drag-and-drop and tap-to-move piece interaction
- Legal move highlighting
- Move history display
- Undo support
- SVG piece rendering

## Screenshots

*Coming soon*

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel)
- For Frozenight: [Rust toolchain](https://rustup.rs/) (to compile the native engine)

### Build and Run

```bash
# Clone the repo
git clone https://github.com/CrispStrobe/CrispChess.git
cd CrispChess

# Get dependencies
flutter pub get

# Run on your platform
flutter run
```

The app works immediately with the built-in Dart engine. No native compilation needed.

### Build Frozenight (optional)

To enable the Frozenight engine (~2960 ELO):

```bash
cd native/frozenight
cargo build --release
# Linux: copy target/release/libfrozenight_ffi.so to your app's lib/ directory
# macOS: copy target/release/libfrozenight_ffi.dylib alongside the app bundle
```

### Build for Web

```bash
flutter build web --release
```

The web build uses the pure Dart engine — no native code required.

## Architecture

```
lib/
  engines/
    chess_engine.dart           # Abstract ChessEngine interface
    dart_engine.dart            # Built-in Dart engine (MIT)
    dart_engine/
      evaluation.dart           # Piece-square tables, material eval
      search.dart               # Alpha-beta, iterative deepening, quiescence
    frozenight_engine.dart      # Frozenight FFI bindings (MIT/Apache-2.0)
  services/
    engine_service.dart         # Engine lifecycle + event stream
  chess/
    chess_game.dart             # Game state (ChangeNotifier)
    game_state.dart             # Immutable UI state with copyWith
    move_analyzer.dart          # Tactical pattern detection
  screens/
    chess_game_screen.dart      # Main game UI
    settings_screen.dart        # Strength & display settings
  widgets/
    chess_board.dart            # Board with RepaintBoundary + drag/drop
    horizontal_evaluation_bar.dart
  main.dart

native/
  frozenight/                   # Rust FFI wrapper for Frozenight engine
    Cargo.toml
    src/lib.rs
    build.sh
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
  Stream<EvalInfo> analyze(String positionCommand, {int? depth});
  void stop();
  void dispose();
}
```

Engines are hot-swappable at runtime via `EngineService.switchEngine()`.

## Testing

```bash
# Run unit and widget tests
flutter test

# Run integration tests (requires a connected device or emulator)
flutter test integration_test/
```

80+ tests covering game logic, engine interface, evaluation, state management, and widgets.

## CI/CD

GitHub Actions builds and tests on every push:

- **Analyze & Test** — Dart analyzer + unit tests
- **Frozenight (Linux)** — Compiles Rust FFI library → `libfrozenight_ffi.so`
- **Frozenight (macOS)** — Compiles Rust FFI library → `libfrozenight_ffi.dylib`
- **Build Android** — Release APK
- **Build iOS** — Release (no codesign)
- **Build macOS** — Release .app
- **Build Linux** — Release tarball
- **Build Web** — Release web app
- **Bundle Linux + Frozenight** — Packages Flutter app with native engine

## License

**MIT** — see [LICENSE](LICENSE).

The app code, built-in Dart engine, and all original code in this repository are MIT licensed. You are free to use, modify, and distribute this software.

### Engine Licenses

| Component | License | Bundled |
|-----------|---------|---------|
| CrispChess app | MIT | Yes |
| CrispEngine (Dart) | MIT | Yes |
| Frozenight | MIT + Apache-2.0 | Yes |
| Stockfish | GPL-3.0 | No (optional download) |

When Stockfish is included in a build, that build must comply with GPL-3.0. Builds without Stockfish are fully MIT.

### Dependencies

All Flutter/Dart dependencies use permissive licenses (BSD-2, BSD-3, MIT). See the [license survey](https://github.com/CrispStrobe/crisp-repos/blob/main/stockfish-license-survey.md) for details.

## Contributing

Contributions welcome. Please open an issue first for major changes.

## Roadmap

- [ ] Play as Black
- [ ] Engine selection in settings UI
- [ ] Opening book integration
- [ ] Time controls
- [ ] PGN export/import
- [ ] Board flip
- [ ] Sound effects
- [ ] Android NDK cross-compilation for Frozenight
- [ ] iOS static library for Frozenight
- [ ] App Store / Play Store release
- [ ] "Buy me a coffee" support
