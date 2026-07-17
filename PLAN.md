# CrispChess — Development Plan

> **License rule**: Every task below MUST stay within MIT license.
> GPL-licensed code (Stockfish, Lc0) is never bundled — only downloaded at
> runtime by the user.  All new dependencies must be MIT, BSD, Apache-2.0,
> or CC0.  Open chess APIs are free and require no license.  No proprietary
> database formats will be implemented.

---

## Completed

### Engine Architecture (7 engines)
- [x] Built-in (pure Dart, alpha-beta + TT, ~1800 ELO)
- [x] Frozenight (Rust NNUE, MIT/Apache-2.0, ~3226 ELO) — WASM + native FFI
- [x] Lynx (C# classical HCE, MIT, ~3350 ELO) — .NET WASM on web + native binary on desktop
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
- [x] CLI interface (`bin/crispchess.dart`) — analyze, play, match, perft, puzzle, fen, board
- [x] REST API server (`bin/server.dart`) — /api/analyze, /api/puzzle, /api/board, /api/perft, /api/fen, /api/health
- [x] Cross-platform HTTP service (dart:io native + web fetch API)

### Board Improvements (Phase 6)
- [x] Board coordinate labels (a-h, 1-8)
- [x] Last move highlighting (warm brown tint on from/to squares)
- [x] Captured pieces tray with material advantage badge (+N)
- [x] Animated hint/analysis arrows on the board (via annotation overlay)
- [x] Capture visual effect (particle burst on capture square)
- [x] Checkmate flourish (glow + boxShadow on mated king square)

### Game Flow (Phase 6)
- [x] Confirmation dialog before New Game (prevent accidental loss)
- [x] Draw offer — engine evaluates and accepts/declines based on eval
- [x] Resignation option with confirmation
- [x] Precise game-end reason (checkmate/stalemate/repetition/50-move/insufficient/resign/draw)
- [x] SAN notation in move history (e4, Nf3 instead of e2e4, g1f3)
- [x] Pre-game side picker (White / Black / Random / Two Player)
- [x] Long-press move list to quick-copy PGN

### Settings (Phase 6)
- [x] "Reset to defaults" button
- [x] "Allow Undo" toggle (disable for discipline mode)
- [x] AMOLED dark theme (pure black background, system/light/dark toggle)

### Post-Game Analysis (Phase 7)
- [x] Post-game summary with accuracy percentage
- [x] Eval chart — plot evaluation across all moves (green/red fill areas)
- [x] Interactive board — tap move to jump to position with preview board
- [x] Per-move classification: brilliant / good / inaccuracy / mistake / blunder
- [x] "Your best move" card with SAN + eval gain
- [x] "Biggest mistake" card with SAN + eval loss
- [x] Live move annotation — classify each player move in real-time
- [x] Show annotation in analysis panel with color/icon per category
- [x] Display alternative move suggestion ("Better: Nf3")
- [x] Store eval per move for chart (no re-analysis needed)
- [x] Undo/redo via game tree FEN snapshots (Y key / right arrow)

### Persistence (Phase 7.5)
- [x] Save all settings to shared_preferences
- [x] Auto-load on app start, auto-save on change

### Training & Puzzles (Phase 8)
- [x] ~1600 tactical puzzles (CC0 database)
- [x] Categories: fork, pin, skewer, mate, endgame, etc.
- [x] Puzzle UI: interactive board, validate moves, 3 attempts
- [x] Puzzle difficulty rating (Glicko-2)
- [x] Daily puzzle (deterministic by date)
- [x] Structured drills by topic (4 built-in drills)
- [x] Position grid with completion state
- [x] Interactive lesson player with branching move trees
- [x] Coach bubble messages at each step with wrong-move feedback
- [x] Post-drill summary screen with accuracy
- [x] Mistakes tracker with spaced repetition (1d/3d/7d/14d/30d intervals)

### Gamification (Phase 9)
- [x] Game persistence (save/restore, resume on startup)
- [x] Game history (last 50 PGNs)
- [x] Bookmarks — save positions to local storage
- [x] XP system: game win/draw/loss, puzzle solve
- [x] Player level tiers (Pawn → Grandmaster, 6 levels)
- [x] Level-up celebration dialog
- [x] Daily login streak with bonus XP
- [x] Achievement system (12 badges)
- [x] Stats screen with level, XP bar, achievement list

### Game Modes (Phase 10)
- [x] Two-player local (pass-and-play with auto-flip)
- [x] Chess960 / Fischer Random position generator (code only)
- [x] King of the Hill detection (code only)
- [x] Three-check detection (code only)

### Advanced Features (Phase 11)
- [x] Opening name display (~50 openings)
- [x] Syzygy tablebase probing via open API (≤7 pieces, native)
- [x] Built-in engine optimizations (null move, PVS, LMR, etc.)
- [x] Pondering
- [x] Multi-PV analysis
- [x] AI Coach (BYOK — Anthropic / OpenAI)

### UI Polish (Phase 12)
- [x] Premove support
- [x] Onboarding tips dialog
- [x] Keyboard shortcuts (Z/H/N/F/A)
- [x] Right-click draw arrows on board
- [x] Rate app prompt

### Internationalization (Phase 13)
- [x] English (en) + German (de)
- [x] Language auto-detected from system locale

### Analysis Workbench (Phase 15)
- [x] Generic UCI engine management (load any binary, UCI handshake, option dialog)
- [x] Engine profile persistence
- [x] Engine manager screen
- [x] `go infinite` support
- [x] Multi-PV display (1–5 lines)
- [x] Multi-engine simultaneous analysis
- [x] Game tree with variations (branch, promote, delete, navigate)
- [x] PGN import/export with full RAV notation
- [x] Position editor (piece palette, castling, EP, FEN I/O)
- [x] Board annotations (arrows, square highlights, NAG, comments)
- [x] PGN database browser (multi-game, search/filter, stats)
- [x] Engine vs engine matches + round-robin tournaments

### Built-in Engine Performance (Phase 16)
- [x] Faster hashing, delta pruning, MVV-LVA, SEE pruning
- [x] Null move pruning, PVS
- [x] Web build optimization (lazy ONNX, cache headers)

---

## Phase 17: Quick Wins — Wire Up Existing Code

_Goal: ship features where the code already exists but the UI doesn't._
_License: all existing code, no new dependencies._

### Chess960 & Variants UI
- [x] Game mode selector: Standard / Chess960 / King of the Hill / Three-Check
- [x] Chess960 — random starting position from `chess960.dart`, displayed before game start
- [x] King of the Hill — win condition active, status message on center-square victory
- [x] Three-Check — check counter UI, win condition active, status message on 3rd check
- [x] Persist selected variant in preferences

### Custom Time Controls
- [x] "Custom" entry in time control picker
- [x] Input fields: base minutes (0–180) + increment seconds (0–60)
- [x] Persist last custom time control in preferences

### Engine Hash & Thread Configuration
- [x] Expose Hash (MB) slider in settings for engines that support it
- [x] Expose Threads slider (1 – platform core count) in settings
- [x] Pass UCI `setoption` commands on engine init
- [x] Per-engine option overrides (already have infrastructure in GenericUciEngine)

---

## Phase 18: Board & Sound Polish

_Goal: close the two most obvious visual/audio gaps._
_License: all assets must be MIT/CC0/CC-BY. Use `just_audio` (MIT) or
`audioplayers` (BSD) for native sound._

### Board Color Themes
- [x] Define 8 board color schemes: Classic Green, Classic Brown, Blue, Gray, Tournament (USCF green/cream), Walnut (wood tone), Ice (light blue/white), Midnight (dark blue/charcoal)
- [x] Board theme picker in settings (grid of mini-previews)
- [x] Apply light-square / dark-square colors to board painter
- [x] Coordinate label color adapts to board theme contrast
- [x] Persist selected board theme in preferences

### Native Sound Effects
- [x] Platform-conditional sound service: Web Audio on web, native SystemSound + HapticFeedback on others
- [x] Conditional import factory for platform-appropriate sound service
- [x] Sound toggle in settings applies to both paths
- [ ] Add `audioplayers` (BSD) for proper audio sample playback (upgrade from SystemSound)
- [ ] Source or synthesize short audio samples for: move, capture, check, castle, promote, game-start, game-end, illegal (MIT/CC0 licensed only)
- [ ] Test audio on Android, iOS, macOS, Linux, Windows

### GIF Export Completion
- [ ] Add `image` package (MIT) for GIF encoding
- [ ] Wire frame generator to actual GIF encoder
- [ ] Share sheet / save-to-file for exported GIF
- [ ] Progress indicator during encoding

---

## Phase 19: PGN & Database Improvements

_Goal: move from clipboard-only to proper file I/O, and expand database capabilities._
_License: `file_picker` (MIT), `share_plus` (BSD)._

### File-Based PGN Import/Export
- [ ] Add `file_picker` (MIT) dependency for native file dialogs
- [ ] "Open PGN file" action — load .pgn from filesystem
- [ ] "Save PGN file" action — write current game to .pgn file
- [ ] Mobile share sheet integration via `share_plus` (BSD) for PGN export
- [ ] Associate .pgn file type on Android/iOS (open in CrispChess)

### Database Enhancements
- [x] Game tagging / favorites — star icon on game history entries
- [x] Filter game history by result (1-0 / 0-1 / ½-½) + favorites-only
- [x] Increase game history limit (50 → 500)
- [x] Bulk PGN export of game history (copy all filtered to clipboard)
- [x] Game History screen with browsable list, load game on tap

### Notation Style Options
- [x] Setting: Algebraic (default) / Figurine Algebraic (piece symbols: ♞f3 instead of Nf3)
- [x] Apply to move list via formatNotation() in move chip display
- [x] Persist in preferences

---

## Phase 20: Puzzle Expansion

_Goal: make the puzzle system world-class._
_License: CC0 puzzle databases. Open puzzle APIs (no auth required)._

### More Puzzles
- [ ] Expand bundled puzzle set from ~1,600 to 10,000+ (CC0 puzzles)
- [ ] Lazy-load puzzles from asset chunks (don't bloat initial download)
- [x] Rating-range filter in puzzle picker (800-1200, 1200-1600, 1600-2000, 2000+)

### Puzzle Rush / Storm Mode
- [x] Timed puzzle sprint: solve as many as possible in 3 minutes
- [x] Lives system: 3 wrong answers = game over
- [x] Score display with personal best tracking
- [ ] Leaderboard (local — personal history of past runs)

### Online Puzzle API Integration
- [ ] Fetch daily puzzle from open puzzle API (supplement local daily puzzle)
- [ ] Fetch puzzle by theme + rating range from open API
- [ ] Offline fallback to bundled puzzles when no network
- [ ] Attribution label for externally sourced puzzles

### Endgame-Specific Training
- [x] Dedicated endgame drill sets: K+Q vs K, K+R vs K, K+P vs K, K+2B vs K
- [x] Progressive difficulty (3 steps per endgame type)
- [ ] K+B+N vs K drill (complex, needs more positions)
- [ ] Checkmate-in-N counter (must find mate within N moves)
- [ ] Tablebase validation of each move (correct if DTZ improves or stays optimal)

### Coordinate Training
- [x] New screen: "Coordinate Trainer"
- [x] Flash a square name (e.g., "f6"), player taps the correct square
- [x] Timed mode: how many correct in 30 seconds
- [x] Score tracking with personal best

---

## Phase 21: Opening Explorer

_Goal: standalone Opening Explorer screen on par with the best in class._
_License: open explorer APIs (free, no auth). All code is MIT._

### Opening Explorer Screen
- [x] New screen accessible from main menu: "Opening Explorer"
- [x] Interactive board at top, move table below
- [x] For each candidate move: show games played, win% / draw% / loss% bar
- [x] Click a move to play it on the board and load next position's stats
- [x] Navigate back through move history

### Data Sources
- [x] Masters game database (via open explorer API — free, no auth)
- [x] Online player database (toggle between Masters / Online)
- [ ] Local/offline fallback: expanded built-in opening book (200+ positions)
- [ ] Cache API responses locally for offline re-use

### Opening Repertoire Trainer
- [ ] User defines repertoire: record moves as White or Black through explorer
- [ ] Save repertoire lines to local storage
- [ ] Training mode: app plays opponent moves, user must recall their repertoire move
- [ ] Spaced repetition for repertoire lines (reuse existing SRS infrastructure)
- [ ] Import repertoire from PGN

---

## Phase 22: Open Chess API Integration

_Goal: connect CrispChess to the open chess ecosystem._
_License: open chess APIs are free and rate-limited (no auth needed for most
endpoints). All code MIT._

### Game Import
- [ ] "Import Games" screen — enter username from supported open platform
- [ ] Fetch recent games via open Games API (NDJSON)
- [ ] Display game list with opponent, result, time control, date
- [ ] Load any game onto the board for analysis
- [ ] Persist imported games in local database

### Tablebase on Web
- [x] Enable Syzygy API calls on web platform (cross-platform HTTP service)
- [x] Same UX: show tablebase result in analysis panel when ≤7 pieces

### Live Tournament Broadcasts
- [ ] Fetch active broadcasts from open Broadcast API
- [ ] Tournament list screen with names, rounds, status
- [ ] Click to watch: live board with moves streaming in
- [ ] Engine eval overlay during broadcast
- [ ] Multi-board view for rounds with multiple games

---

## Phase 23: Training & Learning Expansion

_Goal: deepen the training offering to best-in-class level._
_License: all content must be original or CC0. Code is MIT._

### Blindfold Mode
- [x] Setting toggle: hide pieces on board (blindfold property on ChessBoard)
- [x] Last-move highlight still visible as the only board hint
- [x] Works in play-vs-AI mode (persisted in preferences)

### More Drills
- [ ] Expand from 4 to 20+ drills across categories:
  - Tactics: discovered attack, deflection, decoy, clearance, zwischenzug
  - Endgames: rook endgames, queen vs pawn, opposite-color bishops
  - Openings: Sicilian basics, Queen's Gambit Declined, Caro-Kann, French
- [ ] Drill difficulty ratings (beginner / intermediate / advanced)
- [ ] Drill completion contributes to XP

### AI Coach Enhancements
- [ ] Post-game verbal review: send full PGN to LLM, display narrative analysis
- [ ] "Why is this move bad?" — tap any classified mistake, ask AI Coach to explain
- [ ] Study recommendations: AI Coach suggests what to practice based on game history
- [ ] Opening repertoire suggestions based on play style analysis

### Personalized Improvement Insights
- [ ] Analyze last N games for patterns: common mistake types, weak phases, blunder-prone positions
- [ ] "Your Weaknesses" dashboard: tactics accuracy, endgame conversion rate, opening repertoire breadth
- [ ] Suggested training plan based on weakness analysis
- [ ] Track improvement over time (graphs of accuracy, puzzle rating, etc.)

---

## Phase 24: More Locales

_Goal: broaden addressable market beyond EN/DE._
_License: translations are original content under MIT._

### Priority Languages
- [ ] Spanish (es)
- [ ] French (fr)
- [ ] Portuguese (pt)
- [ ] Russian (ru)
- [ ] Chinese Simplified (zh)
- [ ] Japanese (ja)
- [ ] Korean (ko)
- [ ] Hindi (hi)
- [ ] Italian (it)
- [ ] Dutch (nl)
- [ ] Polish (pl)
- [ ] Turkish (tr)

### Translation Infrastructure
- [ ] Verify all user-facing strings are in ARB files (no hardcoded strings)
- [ ] Contribution guide for community translations
- [ ] Locale-specific piece notation (e.g., German uses S for knight, not N)

---

## Phase 25: Distribution

_Goal: get CrispChess into every major app store._
_License: MIT app, GPL engines downloaded at runtime — compliant for all stores._

### App Stores
- [ ] Google Play Store listing + screenshots
- [ ] Apple App Store listing + screenshots
- [ ] F-Droid (fully open source build, no proprietary dependencies)
- [ ] Flathub (Linux)
- [ ] Snap Store (Linux)
- [ ] Microsoft Store (Windows)
- [ ] Homebrew Cask (macOS)

### PWA
- [ ] Service worker for offline web support (if Flutter SW conflict resolved)
- [ ] Web app manifest with CrispChess branding
- [ ] "Install as app" prompt on supported browsers

---

## Phase 26: Online Multiplayer (Strategic)

_Goal: human vs human play without building full server infrastructure._
_License: open Board API is free. All code MIT._

### Open Platform Board API Integration
- [ ] OAuth2 login with open chess platform (PKCE flow)
- [ ] Seek / challenge creation via Board API
- [ ] Real-time game stream (NDJSON events)
- [ ] Move submission via Board API
- [ ] Chat display (optional)
- [ ] Game result handling (resign, draw offer, timeout)
- [ ] Rating display from user profile

### Local Network Play
- [ ] Discover opponents on same Wi-Fi (mDNS / UDP broadcast)
- [ ] Direct WebSocket connection between devices
- [ ] No server required — fully peer-to-peer
- [ ] Time sync for clock accuracy

---

## Phase 27: Advanced Database (Strategic)

_Goal: professional-grade database for power users._
_License: `sqflite` (BSD) or `drift` (MIT) for SQLite. All code MIT._

### SQLite Game Database
- [ ] Migrate from shared_preferences JSON to SQLite for game storage
- [ ] Store games, positions, tags, annotations efficiently
- [ ] Full-text search on player names, events, annotations
- [ ] Position search (find games reaching a given FEN)
- [ ] Handle 100K+ games without performance degradation

### Polyglot Opening Book Support
- [ ] Read .bin Polyglot opening books (format is public domain)
- [ ] Display book moves with weights in Opening Explorer
- [ ] Multiple books simultaneously (merge results)
- [ ] User can load their own .bin files

### DGT Board Integration
- [ ] Bluetooth LE connection to DGT boards
- [ ] Read piece positions from board
- [ ] Sync moves between physical board and app
- [ ] Clock display sync

---

## Phase 28: Built-in Engine — Bitboard Core & Strength

_Goal: make the built-in ("Built-in" / Dart) engine fast, correct, and strong.
The engine now lives in the extracted `crisp_chess_engine` package (pub.dev)._
_License: all engine code MIT, no new dependencies._

### Completed (this cycle)
- [x] Extracted the engine to the `crisp_chess_engine` package (pub.dev), app depends on it
- [x] **0.2.0** — fixed a search bug that returned moves for the *wrong side*
  (null-move via `load()` wiped undo history; `evaluate()` called
  `in_threefold_repetition`, restoring `turn` behind the search). TT key now
  includes castling + en-passant. ~5x faster.
- [x] Drive play by **time, not fixed depth** — level-scaled `movetime`; fixes
  the tablet "hang" and Stockfish being slow at low Skill Level
- [x] Maia3: feed the *real* consecutive game history (from the position
  command) instead of engine-side accumulation that skipped every other ply;
  removed the dead JS-bridge Maia3 engine (native stub that threw)
- [x] **0.3.0** — native **bitboard engine**, perft-verified (startpos, Kiwipete,
  positions 3-6); 20-60x nodes/sec (depth-8 midgame ~37s → ~0.8s). Wired via
  conditional import: native uses bitboards, web keeps the chess-package search
  (dart2js can't represent 64-bit ints)
- [x] **0.4.0** — aspiration windows + SEE quiescence pruning (~32% fewer nodes
  to a given depth → deeper in the same time budget)

### Pending / doable
- [ ] **Evaluation terms** (biggest strength lever now search is fast): bishop
  pair, mobility, passed pawns, doubled/isolated pawns, basic king safety
  (pawn shield + attacker count). Verify each with a self-play match
  (new eval must score > 50% vs old).
- [ ] SEE-based capture ordering in the main search (demote losing captures
  below quiet moves)
- [ ] Clock-aware time management — allocate the per-move budget from remaining
  clock + increment, not a flat per-level budget
- [ ] Endgame knowledge: KPK / KQK / KRK heuristics so won endings don't dawdle
  (the K+P-vs-K horizon that evaluates ~0)
- [ ] Countermove / continuation-history move ordering; adaptive null-move R;
  futility + late-move pruning at frontier nodes
- [ ] Magic bitboards for slider attacks (another ~2-4x nps; higher complexity —
  only if a concrete need appears)
- [ ] Expanded opening book feeding the engine (currently ~40 positions)
- [ ] Web parity: evaluate `dart2wasm` (real 64-bit ints) so web could also run
  the bitboard engine instead of the slower chess-package search

---

## Backlog (Not Prioritized)

_Items that don't fit current strategy or have low ROI._

- [ ] 3D board rendering (high effort, low usage)
- [ ] Bughouse / 4-player chess (very high effort, niche demand)
- [ ] WinBoard/XBoard engine protocol (legacy, near-zero demand)
- [ ] Coaching marketplace (business infrastructure, not a code problem)
- [ ] Social features — friends, chat, clubs (requires backend, not core identity)
- [ ] Video lessons (content creation bottleneck, not code)
- [ ] Decorative background watermark (cosmetic, low priority)
- [ ] Staggered entry animations on game summary (cosmetic, low priority)
