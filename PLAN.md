# CrispChess — Standalone App Plan

## Engine Architecture

```
CrispChess App (MIT)
  ├── CrispEngine (Dart, built-in, ~1600 ELO)
  ├── Frozenight (Rust FFI, MIT/Apache-2.0, ~2960 ELO)
  └── Stockfish (C++ FFI, GPL-3.0, optional, non-iOS)
```

## Progress

### Phase 1: Project Setup & Engine Interface
- [x] Create repo, copy app code
- [x] Remove stockfish package dependency
- [x] Define ChessEngine abstract interface
- [x] Define EngineState enum
- [x] Refactor EngineService to use ChessEngine interface
- [x] Refactor chess_game_screen.dart — no direct Stockfish refs
- [x] Update imports (stockfish_example -> crispchess)
- [x] Settings screen: engine selector dropdown

### Phase 2: Built-in Dart Engine (MIT)
- [x] Alpha-beta pruning with iterative deepening
- [x] Piece-square tables for positional evaluation
- [x] Move ordering (MVV-LVA, killer moves, history heuristic)
- [x] Quiescence search
- [x] Runs in isolate via compute()
- [x] Transposition table
- [x] Unit tests for evaluation, search
- [ ] Integration test: engine plays a full game

### Phase 3: Frozenight Integration (MIT/Apache-2.0)
- [x] Rust FFI wrapper (native/frozenight/)
- [x] Dart FFI bindings (FrozenightEngine)
- [x] CI compiles for Linux + macOS
- [x] Bundle job packages .so with Flutter build
- [ ] Android NDK cross-compilation
- [ ] iOS static library

### Phase 4: Optional Stockfish (GPL, non-iOS)
- [ ] StockfishEngine wrapping stockfish package
- [ ] Conditional import
- [ ] GPL notice in settings
- [ ] Exclude from iOS builds

### Phase 5: App Store & Web
- [x] Vercel deploy (https://crispchess.vercel.app)
- [x] CI/CD for all platforms + Rust
- [x] WASM headers in vercel.json
- [ ] App icon and splash screen
- [ ] Buy me a coffee / tip jar
- [x] Privacy policy
- [x] Release workflow with binaries
- [x] About screen with licenses, imprint, privacy
- [x] WASM web build
