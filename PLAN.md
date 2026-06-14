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
- [x] Move hints, undo, abort
- [x] 8 piece themes (MIT/CC0/CC-BY)
- [x] Responsive layout (desktop + mobile)
- [x] About screen with selectable git hash

### Infrastructure
- [x] CI: all platforms (Android/iOS/macOS/Linux/Windows/Web WASM)
- [x] CI: Frozenight builds for 7 targets
- [x] Vercel auto-deploy
- [x] GPL compliance (no GPL code bundled, Stockfish downloaded at runtime)
- [x] THIRD_PARTY_LICENSES.md
- [x] Store release prep (bundle IDs, metadata)

---

## Phase 6: In-Game Polish (quick wins)

### Board Improvements
- [ ] Board coordinate labels (a-h, 1-8) with toggle in settings
- [ ] Last move highlighting (tint from/to squares)
- [ ] Captured pieces tray with material advantage badge (+N)
- [ ] Animated hint/analysis arrows on the board (L-shaped for knight moves)
- [ ] Capture visual effect (particle burst on capture square)
- [ ] Checkmate flourish (glow on mated king + shockwave ring)

### Game Flow
- [ ] Confirmation dialog before New Game / Exit (prevent accidental loss)
- [ ] Draw offer — engine evaluates and accepts/declines based on eval
- [ ] Resignation option
- [ ] Precise game-end reason (checkmate/stalemate/timeout/repetition/50-move/insufficient/draw)
- [ ] Pre-game side picker (White / Black / Random)
- [ ] Long-press move list to quick-copy PGN

### Player Identity
- [ ] Player name chips above/below board (avatar + name + clock)
- [ ] Pulsing indicator when it's your turn
- [ ] Spinning ring on opponent avatar while engine thinks

### Settings Additions
- [ ] "Reset to defaults" button
- [ ] "Allow Undo" toggle (disable for discipline mode)
- [ ] AMOLED dark theme (pure black background)

## Phase 7: Post-Game Analysis

### Debrief Screen
- [ ] Post-game summary with accuracy percentage
- [ ] Eval chart — plot evaluation across all moves (white/black fill areas)
- [ ] Interactive board — tap any move in the list to jump to that position
- [ ] Per-move classification: brilliant / good / inaccuracy / mistake / blunder
- [ ] "Your best move" card with SAN + explanation
- [ ] "Biggest mistake" card with SAN + what was better
- [ ] Staggered entry animations for each section

### Live Move Annotation
- [ ] Classify each player move in real-time (compare to engine's best)
- [ ] Show annotation in analysis panel with color/icon per category
- [ ] Display alternative move suggestion ("Better: Nf3")

### History Snapshots
- [ ] Store eval before/after each move (no re-analysis needed for review)
- [ ] Undo/redo via snapshot stack (not replay from scratch)

## Phase 8: Training & Puzzles

### Puzzle System
- [ ] Bundle 1000+ tactical puzzles (FEN + solution moves, CC0 source)
- [ ] Categories: fork, pin, skewer, discovery, mate-in-1/2/3, endgame
- [ ] Puzzle UI: show position, validate player's move sequence
- [ ] Puzzle difficulty rating (Glicko-2 or similar)
- [ ] Daily puzzle — random puzzle shown on app open

### Drill Mode
- [ ] Structured drills by topic (opening/middlegame/endgame)
- [ ] Position grid with completion state (open/completed)
- [ ] Interactive lesson player with branching move trees
- [ ] Coach bubble messages at each step with arrows/highlights
- [ ] Post-drill summary screen

### Mistakes Tracker
- [ ] Persist blunders across games (FEN, your move, better move, explanation)
- [ ] "My Mistakes" screen — list active and resolved mistakes
- [ ] Resolving a mistake (re-solving it correctly) marks it done
- [ ] Spaced repetition — re-present failed puzzles at increasing intervals

## Phase 9: Gamification & Persistence

### Game Persistence
- [ ] Save/restore game state to local storage (Hive or shared_preferences)
- [ ] "Continue last game" card on home screen with mini board preview
- [ ] Game history list — review past games
- [ ] Bookmarks — save interesting positions

### XP & Progression
- [ ] XP system: game win, draw, loss (participation), puzzle solve, lesson complete
- [ ] Player level tiers (Pawn → Knight → Bishop → Rook → Queen → Grandmaster)
- [ ] Level-up celebration dialog
- [ ] Daily login streak with bonus XP

### Achievements
- [ ] Achievement system with progress tracking
- [ ] Examples: first win, win streaks, lesson milestones, accuracy thresholds
- [ ] Achievement badges displayed in profile

## Phase 10: Game Modes

### Two-Player Local
- [ ] Pass-and-play mode on same device
- [ ] Auto-flip board between turns
- [ ] Optional chess clock for local games

### Variants (future)
- [ ] Chess960 / Fischer Random
- [ ] King of the Hill
- [ ] Three-check

## Phase 11: Advanced Features

### Opening Explorer
- [ ] Show opening name for current position (ECO codes)
- [ ] Opening statistics (win/draw/loss % from master games)
- [ ] Suggested book moves with popularity bars

### Endgame Tablebases
- [ ] Syzygy tablebase probing for ≤7 pieces
- [ ] Download tablebases on demand
- [ ] Perfect endgame play indicator

### Engine Improvements
- [ ] Built-in engine: null-move pruning, late move reductions
- [ ] Pondering (engine thinks during opponent's turn)
- [ ] Multi-PV analysis (show top N lines)

### AI Coach (BYOK)
- [ ] LLM-powered game analysis — send FEN/PGN, get natural language feedback
- [ ] "Ask Coach" bottom sheet during game (scoped per game)
- [ ] Bring-your-own-key model (user provides API key)
- [ ] Privacy-first: data usage disclosure, no server-side storage

## Phase 12: UI Polish

### Visual
- [ ] Dark theme with layered depth tokens (deepest → surface → raised)
- [ ] Press-scale tap animations on interactive elements
- [ ] Premove support (queue move while opponent thinks)
- [ ] Decorative background watermark (subtle chess piece, low opacity)
- [ ] SAN notation in move list (instead of raw UCI)

### UX
- [ ] Onboarding — brief intro on first launch
- [ ] Keyboard shortcuts (web/desktop)
- [ ] Right-click draw arrows on board (analysis mode)
- [ ] Rate app prompt after a win (contextual, non-intrusive)

## Phase 13: Distribution

### App Stores
- [ ] Google Play Store listing + screenshots
- [ ] Apple App Store listing + screenshots
- [ ] F-Droid (fully open source build)
- [ ] Microsoft Store / Snap / Flatpak

### Sharing
- [ ] Share game as image (board screenshot)
- [ ] Share game as animated GIF
- [ ] Online chess platform API integration (import games, puzzles)
