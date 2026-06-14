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
- [x] Board coordinate labels (a-h, 1-8)
- [x] Last move highlighting (warm brown tint on from/to squares)
- [x] Captured pieces tray with material advantage badge (+N)
- [ ] Animated hint/analysis arrows on the board (L-shaped for knight moves)
- [ ] Capture visual effect (particle burst on capture square)
- [ ] Checkmate flourish (glow on mated king + shockwave ring)

### Game Flow
- [x] Confirmation dialog before New Game (prevent accidental loss)
- [x] Draw offer — engine evaluates and accepts/declines based on eval
- [x] Resignation option with confirmation
- [x] Precise game-end reason (checkmate/stalemate/repetition/50-move/insufficient/resign/draw)
- [x] SAN notation in move history (e4, Nf3 instead of e2e4, g1f3)
- [x] Pre-game side picker (White / Black / Random / Two Player)
- [x] Long-press move list to quick-copy PGN

### Settings Additions
- [x] "Reset to defaults" button
- [x] "Allow Undo" toggle (disable for discipline mode)
- [x] AMOLED dark theme (pure black background, system/light/dark toggle)

## Phase 7: Post-Game Analysis

### Debrief Screen
- [x] Post-game summary with accuracy percentage
- [x] Eval chart — plot evaluation across all moves (green/red fill areas)
- [ ] Interactive board — tap move to jump to position (TODO)
- [x] Per-move classification: brilliant / good / inaccuracy / mistake / blunder
- [x] "Your best move" card with SAN + eval gain
- [x] "Biggest mistake" card with SAN + eval loss
- [ ] Staggered entry animations (lower priority)

### Live Move Annotation
- [x] Classify each player move in real-time (compare to engine's best)
- [x] Show annotation in analysis panel with color/icon per category
- [x] Display alternative move suggestion ("Better: Nf3")

### History Snapshots
- [x] Store eval per move for chart (no re-analysis needed)
- [ ] Undo/redo via snapshot stack (not replay from scratch)

## Phase 7.5: Player Preferences Persistence (DONE)

- [x] Save all settings to shared_preferences (engine, variant, strength, theme, etc.)
- [x] Auto-load on app start, auto-save on change
- [x] Reset to defaults button

## Phase 8: Training & Puzzles

### Puzzle System
- [x] 200 tactical puzzles from Lichess CC0 database
- [x] Categories: fork, pin, skewer, mate, endgame, etc.
- [x] Puzzle UI: interactive board, validate moves, 3 attempts
- [x] Puzzle difficulty rating (Lichess Glicko-2)
- [x] Daily puzzle (deterministic by date)

### Drill Mode
- [ ] Structured drills by topic (opening/middlegame/endgame)
- [ ] Position grid with completion state (open/completed)
- [ ] Interactive lesson player with branching move trees
- [ ] Coach bubble messages at each step with arrows/highlights
- [ ] Post-drill summary screen

### Mistakes Tracker
- [x] Persist blunders tracker in shared_preferences
- [ ] "My Mistakes" screen — list active and resolved mistakes
- [ ] Resolving a mistake (re-solving it correctly) marks it done
- [ ] Spaced repetition — re-present failed puzzles at increasing intervals

## Phase 9: Gamification & Persistence

### Game Persistence
- [x] Save/restore game state to shared_preferences
- [x] Resume saved game dialog on startup
- [x] Game history (last 50 PGNs saved locally)
- [x] Bookmarks — save positions to local storage

### XP & Progression
- [x] XP system: game win/draw/loss, puzzle solve
- [x] Player level tiers (Pawn → Grandmaster, 6 levels)
- [ ] Level-up celebration dialog (lower priority)
- [x] Daily login streak with bonus XP

### Achievements
- [x] Achievement system with progress tracking (12 badges)
- [x] Examples: first win, win streaks, puzzle milestones, XP levels
- [x] Stats screen with level, XP bar, and achievement list

## Phase 10: Game Modes

### Two-Player Local
- [x] Pass-and-play mode on same device
- [x] Auto-flip board between turns in two-player mode
- [x] Chess clock available for local games

### Variants (future)
- [ ] Chess960 / Fischer Random
- [ ] King of the Hill
- [ ] Three-check

## Phase 11: Advanced Features

### Opening Explorer
- [x] Show opening name for current position (~35 openings)
- [x] Opening statistics (win/draw/loss % from master games)
- [x] Opening stats with win/draw/loss percentages

### Endgame Tablebases
- [x] Syzygy tablebase probing via Lichess API (≤7 pieces)
- [x] Tablebase queries via API (no download needed)
- [x] Perfect endgame result indicator (win/draw/loss from tablebase)

### Engine Improvements
- [x] Built-in engine: reverse futility pruning, late move reductions
- [ ] Pondering (engine thinks during opponent's turn)
- [x] Multi-PV analysis (Stockfish MultiPV)

### AI Coach (BYOK)
- [ ] LLM-powered game analysis — send FEN/PGN, get natural language feedback
- [ ] "Ask Coach" bottom sheet during game (scoped per game)
- [ ] Bring-your-own-key model (user provides API key)
- [ ] Privacy-first: data usage disclosure, no server-side storage

## Phase 12: UI Polish

### Visual
- [x] Dark theme with AMOLED black (system/light/dark)
- [ ] Press-scale tap animations on interactive elements
- [ ] Premove support (queue move while opponent thinks)
- [ ] Decorative background watermark (subtle chess piece, low opacity)
- [x] SAN notation in move list and status messages

### UX
- [x] Onboarding — tips dialog on first launch
- [x] Keyboard shortcuts (Z=undo, H=hint, N=new, F=flip, A=analysis)
- [ ] Right-click draw arrows on board (analysis mode)
- [ ] Rate app prompt after a win (contextual, non-intrusive)

## Phase 13: Internationalization

- [x] ARB files for English and German (90+ strings)
- [x] English (en) as default locale
- [x] German (de) translation
- [x] Language auto-detected from system locale
- [x] All UI labels, messages, settings translated

## Phase 14: Distribution

### App Stores
- [ ] Google Play Store listing + screenshots
- [ ] Apple App Store listing + screenshots
- [ ] F-Droid (fully open source build)
- [ ] Microsoft Store / Snap / Flatpak

### Sharing
- [ ] Share game as image (board screenshot)
- [ ] Share game as animated GIF
- [ ] Online chess platform API integration (import games, puzzles)
