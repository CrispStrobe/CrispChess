# CrispChess — Development Plan

## Completed

### Engine Architecture (6 engines)
- [x] Built-in (pure Dart, alpha-beta + TT, ~1800 ELO)
- [x] Frozenight (Rust NNUE, MIT/Apache-2.0, ~3226 ELO) — WASM + native FFI
- [x] Stockfish (GPL-3.0, downloaded from CDN at runtime, never bundled)
- [x] Maia3 JS (neural net via JS bridge, web only)
- [x] Maia3 Dart (pure Dart + ONNX Runtime, all platforms, 5m/23m/79m variants)
- [x] Lc0 (MCTS + Maia ONNX weights, 1100-1900 ELO, web + native)

### Core Features
- [x] Abstract ChessEngine interface with hot-swapping
- [x] Opening book (~40 positions, weighted moves)
- [x] Chess clock (12 presets: bullet/blitz/rapid/classical + unlimited)
- [x] PGN export/import (clipboard)
- [x] Board flip
- [x] Sound effects (Web Audio API tone synthesis)
- [x] Move animation with adjustable speed (instant/fast/normal/slow)
- [x] Analysis panel toggle (eval/depth/bestmove)
- [x] Play as White or Black
- [x] Move hints
- [x] Undo
- [x] 8 piece themes (MIT/CC0/CC-BY)
- [x] Responsive layout (desktop + mobile)
- [x] About screen with selectable git hash

### Infrastructure
- [x] CI: all platforms (Android/iOS/macOS/Linux/Windows/Web WASM)
- [x] CI: Frozenight builds for 7 targets (WASM, Linux, macOS, iOS, Android, Windows)
- [x] Vercel auto-deploy
- [x] GPL compliance (no GPL code bundled, Stockfish downloaded at runtime)
- [x] THIRD_PARTY_LICENSES.md
- [x] Store release prep (bundle IDs, metadata)

---

## Phase 6: Training & Puzzles

### Puzzle System
- [ ] Puzzle database — bundle 1000+ tactical puzzles (FEN + solution moves)
  - Source: open puzzle databases (CC0)
  - Categories: fork, pin, skewer, discovery, mate-in-1/2/3, endgame
  - Store as compact binary or JSON asset
- [ ] Puzzle UI screen — show position, player finds the right move(s)
  - Highlight wrong moves in red, correct in green
  - Show solution after 3 attempts or on request
  - "Next puzzle" / "Retry" buttons
- [ ] Puzzle difficulty rating (Glicko-2 or similar)
- [ ] Daily puzzle — random puzzle shown on app open

### Drill Mode
- [ ] Structured drills by topic (opening/middlegame/endgame)
- [ ] Position grid with completion state (open/completed)
- [ ] Progress tracking — persist locally (shared_preferences or SQLite)
- [ ] Resume unfinished drill on app relaunch
- [ ] Post-drill summary screen

### Spaced Repetition
- [ ] Track which puzzles the user got wrong
- [ ] Re-present failed puzzles at increasing intervals
- [ ] Accuracy stats per category

## Phase 7: Game Modes & Social

### Two-Player Local
- [ ] Pass-and-play mode on same device
- [ ] Auto-flip board between turns
- [ ] Optional chess clock for local games

### Game Persistence
- [ ] Save/restore game state to local storage
- [ ] Game history list — review past games
- [ ] Bookmarks — save interesting positions

### Post-Game Analysis
- [ ] Post-game summary screen (moves, blunders, accuracy)
- [ ] Full game analysis — engine evaluates every move
- [ ] Move quality annotations (brilliant/good/inaccuracy/mistake/blunder)
- [ ] Best move comparison (your move vs engine's suggestion)

## Phase 8: UI Polish

### Visual
- [ ] Dark theme with layered depth tokens
- [ ] Press-scale tap animations on interactive elements
- [ ] Board coordinate labels (a-h, 1-8)
- [ ] Last move highlighting (from/to square tint)
- [ ] Premove support (queue move while opponent thinks)
- [ ] Captured pieces display

### UX
- [ ] Onboarding — brief intro on first launch
- [ ] Keyboard shortcuts (web/desktop)
- [ ] Right-click draw arrows on board (analysis)
- [ ] Move input by typing algebraic notation

## Phase 9: Advanced Engine Features

### Opening Explorer
- [ ] Show opening name for current position (ECO codes)
- [ ] Opening statistics (win/draw/loss % from master games)
- [ ] Suggested book moves with popularity bars

### Endgame Tablebases
- [ ] Syzygy tablebase probing for ≤7 pieces
- [ ] Download tablebases on demand (~1GB for 6-piece)
- [ ] Perfect endgame play indicator

### Engine Improvements
- [ ] Built-in engine: null-move pruning, late move reductions
- [ ] Built-in engine: endgame-specific evaluation
- [ ] Pondering (engine thinks during opponent's turn)
- [ ] Multi-PV analysis (show top N lines)

## Phase 10: Distribution

### App Stores
- [ ] Google Play Store listing + screenshots
- [ ] Apple App Store listing + screenshots
- [ ] F-Droid (fully open source build)
- [ ] Microsoft Store / Snap / Flatpak

### Community
- [ ] Online chess platform API integration (import games, puzzles)
- [ ] Share game as image (board screenshot)
- [ ] Share game as animated GIF
