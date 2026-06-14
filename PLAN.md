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
- [x] Capture visual effect (particle burst on capture square)
- [x] Checkmate flourish (glow + boxShadow on mated king square)

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
- [x] Interactive board — tap move to jump to position with preview board
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
- [x] "My Mistakes" screen — list tracked blunders
- [x] Resolving a mistake (re-solving) — spaced repetition system
- [x] Spaced repetition — re-present at 1d/3d/7d/14d/30d intervals

## Phase 9: Gamification & Persistence

### Game Persistence
- [x] Save/restore game state to shared_preferences
- [x] Resume saved game dialog on startup
- [x] Game history (last 50 PGNs saved locally)
- [x] Bookmarks — save positions to local storage

### XP & Progression
- [x] XP system: game win/draw/loss, puzzle solve
- [x] Player level tiers (Pawn → Grandmaster, 6 levels)
- [x] Level-up celebration dialog with tier icon
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
- [x] Chess960 / Fischer Random position generator
- [x] King of the Hill (win by king on d4/d5/e4/e5)
- [x] Three-check (win by giving check 3 times)

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
- [x] Pondering (engine analyzes during opponent's turn)
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
- [x] Premove support (queue move while opponent thinks)
- [ ] Decorative background watermark (subtle chess piece, low opacity)
- [x] SAN notation in move list and status messages

### UX
- [x] Onboarding — tips dialog on first launch
- [x] Keyboard shortcuts (Z=undo, H=hint, N=new, F=flip, A=analysis)
- [x] Right-click draw arrows on board (analysis mode)
- [x] Rate app prompt after 3rd win (non-intrusive snackbar)

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
- [x] Share game as image (board screenshot via RepaintBoundary)
- [ ] Share game as animated GIF
- [ ] Online chess platform API integration (import games, puzzles)

---

## Phase 15: Analysis Workbench

_Goal: transform CrispChess from "play the computer" into a proper analysis
platform on par with Nibbler, En Croissant, BanksiaGUI, and Cutechess._

### Generic UCI Engine Management
- [x] Load any UCI engine binary from disk (GenericUciEngine class)
- [x] UCI handshake: send `uci`, parse `id name`, `id author`, `option` lines
- [x] UCI option configuration dialog — auto-generated from engine's `option` list
- [x] Common options surfaced: Hash (MB), Threads, MultiPV, SyzygyPath
- [x] Engine profile persistence — save name, path, and option overrides
- [x] Engine manager screen — add / remove / configure
- [x] `go infinite` support — engine runs until user stops (not just `go depth N`)

### Multi-PV Display
- [x] Send `setoption name MultiPV value N` (user-configurable, 1–5)
- [x] Display top N engine lines as full move sequences with eval + depth
- [x] Highlight principal variation on the board (blue arrow for best move)

### Multi-Engine Analysis
- [x] Run 2+ engines simultaneously on the same position
- [x] Split analysis panel — each engine gets its own eval / PV display
- [x] Compare evaluations side-by-side (useful for engine testing)

### Game Tree & Variations
- [x] Replace linear move history with a tree structure (nodes + children)
- [x] Add variation on any move — branches shown inline or collapsible
- [x] Navigate variations (click to enter, back to exit)
- [x] Promote/delete variations
- [x] PGN import/export with full variation support (RAV notation)

### Position Editor
- [x] Board setup mode — tap piece type, then tap square to place
- [x] Piece palette (all 12 pieces + eraser)
- [x] Set side to move, castling rights, en passant square
- [x] Validate position legality before starting analysis/game
- [x] FEN input field — paste FEN string to load any position
- [x] FEN output — copy current position as FEN

### Board Annotations
- [x] Right-click tap to color squares
- [x] Annotation overlay painter (arrows + highlights)
- [x] Right-click drag to draw arrows (green/yellow/red)
- [x] Text comments per move (stored in game tree)
- [x] NAG support ($1 = !, $2 = ?, etc.) in game tree nodes
- [x] Clear annotations button

### PGN Database
- [x] Open .pgn database (paste multi-game PGN)
- [x] Game list view — players, result, date, ECO, event
- [x] Search/filter by player name, result
- [x] Click game to load onto board
- [x] Database statistics (most common openings, win rates)

### Engine vs Engine
- [x] Match mode — two engines play N games (alternating colors)
- [x] Configurable depth per engine
- [x] Live board display during match
- [x] Results table (wins/draws/losses, score totals)
- [x] Tournament mode — round-robin with 3+ engines, standings table

### PGN Database
- [x] Open .pgn database (paste multi-game PGN)
- [x] Game list view — players, result, date, ECO, event
- [x] Search/filter by player name, result
- [x] Click game to load onto board
- [x] Database statistics (result distribution, top ECOs, most active players)

## Phase 16: Built-in Engine Performance

### Search Optimization
- [x] Faster `_quickHash()` — hash only piece placement + turn (skip castling/EP)
- [x] Delta pruning in quiescence — skip if queen capture can't raise alpha
- [x] MVV-LVA scoring for captures in quiescence (pre-sorted)
- [x] Reusable static Map in `_makeMove()` — reduce GC pressure
- [x] Cache `_moveToUci()` — pre-compute in `_ScoredMove` (computed once per move)
- [x] SEE-like pruning — skip losing captures in quiescence
- [x] Null move pruning — skip turn, search at R=2 reduced depth
- [x] Principal variation search (PVS) — zero-width window for non-first moves

### Web Build Optimization
- [x] Exclude `ort.min.js.map` (1.3 MB source map) from production deploy
- [x] Add `Cache-Control` headers for immutable assets (WASM, SVG, JS bundles)
- [x] Lazy-load ONNX Runtime — only download when Maia3/Lc0 engine is selected
- [x] Service worker for PWA offline support
