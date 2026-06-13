# CrispChess — Standalone App Plan

## Goal

Extract the chess app from the Stockfish plugin repo into a standalone, MIT-licensed
app with pluggable engine backends. Publishable to App Store / Play Store with
optional "buy me a coffee" support.

## Engine Architecture

```
┌─────────────────────────────────────────────┐
│  CrispChess App (MIT)                       │
│  ┌─────────────────────────────────────┐    │
│  │  abstract ChessEngine               │    │
│  │  ├── DartEngine (built-in, MIT)     │    │
│  │  ├── FrozenightEngine (MIT/Apache)  │    │
│  │  └── StockfishEngine (GPL, opt-in)  │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

### Engine Backends

| Engine | License | ELO | Language | Platforms | Bundled? |
|--------|---------|-----|----------|-----------|---------|
| DartEngine | MIT | ~1400-1800 | Dart | All (incl. web) | Yes |
| Frozenight | MIT/Apache-2.0 | ~2960 | Rust via FFI | iOS, Android, macOS, Linux, Windows | Yes |
| Stockfish | GPL-3.0 | ~3600 | C++ via FFI | Android, macOS, Linux, Windows (NOT iOS) | No (download) |

### Why not Stockfish on iOS?
iOS prohibits spawning separate processes. Linking GPL code into the app binary
makes the entire app GPL. Frozenight at ~2960 ELO is strong enough for all
practical purposes on iOS.

---

## Implementation Phases

### Phase 1: Project Setup & Engine Interface
- [x] Create repo, copy app code
- [ ] Remove stockfish package dependency
- [ ] Define ChessEngine abstract interface
- [ ] Define EngineState enum (replaces StockfishState)
- [ ] Refactor EngineService to use ChessEngine interface
- [ ] Refactor chess_game_screen.dart to remove all direct Stockfish refs
- [ ] Update imports throughout (stockfish_example -> crispchess)
- [ ] Settings screen: engine selector

### Phase 2: Built-in Dart Engine (MIT)
- [ ] Implement DartEngine with minimax + alpha-beta pruning
- [ ] Piece-square tables for positional evaluation
- [ ] Iterative deepening + move ordering
- [ ] Quiescence search (captures-only at leaf nodes)
- [ ] Transposition table
- [ ] Target: ~1400-1800 ELO, depth 5-8 in <2s on mobile
- [ ] Unit tests for evaluation, search, move ordering
- [ ] Integration test: engine plays a full game

### Phase 3: Frozenight Integration (MIT/Apache-2.0)
- [ ] Add Rust build toolchain for iOS/Android/desktop
- [ ] Create Dart FFI bindings for Frozenight
- [ ] Implement FrozenightEngine using UCI protocol over FFI
- [ ] Add NNUE network file management
- [ ] Test on all platforms
- [ ] CI/CD for Rust cross-compilation

### Phase 4: Optional Stockfish (GPL, non-iOS)
- [ ] Implement StockfishEngine wrapping existing stockfish package
- [ ] Conditional import: only when stockfish package installed
- [ ] Settings UI: engine selection dropdown
- [ ] Show GPL notice when Stockfish selected
- [ ] Exclude from iOS builds entirely

### Phase 5: App Store Readiness
- [ ] App icon and splash screen
- [ ] Buy me a coffee / tip jar integration
- [ ] App Store metadata
- [ ] Play Store listing
- [ ] Privacy policy
- [ ] Release workflow

---

## ChessEngine Interface

```dart
enum EngineState { idle, initializing, ready, thinking, error, disposed }

abstract class ChessEngine {
  String get name;
  String get version;
  String get license;
  EngineState get state;
  ValueNotifier<EngineState> get stateNotifier;

  Future<void> initialize();

  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  });

  Stream<EvalInfo> analyze(String positionCommand, {int? depth});

  void stop();
  void dispose();
}

class EvalInfo {
  final double score;     // in pawns, from white's perspective
  final int depth;
  final String? bestMove;
  final String? pv;
}
```

## Target File Structure

```
lib/
  engines/
    chess_engine.dart        # Abstract interface + EvalInfo + EngineState
    dart_engine.dart         # Built-in Dart minimax engine
    dart_engine/
      evaluation.dart        # Piece-square tables, material
      search.dart            # Alpha-beta, iterative deepening
      transposition.dart     # Hash table
    frozenight_engine.dart   # Frozenight FFI wrapper
    stockfish_engine.dart    # Optional Stockfish wrapper
  services/
    engine_service.dart      # High-level service using ChessEngine
  chess/
    chess_game.dart
    game_state.dart
    move_analyzer.dart
  screens/
    chess_game_screen.dart
    settings_screen.dart
  widgets/
    chess_board.dart
    horizontal_evaluation_bar.dart
  main.dart
```

## Licensing

- App code: MIT
- Frozenight: MIT + Apache-2.0 (bundled)
- Stockfish: GPL-3.0 (optional, NOT on iOS)
- chess (Dart pkg): BSD-2-Clause
- flutter_svg: MIT
- All other deps: BSD-3-Clause
