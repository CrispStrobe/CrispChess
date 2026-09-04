# Changelog

## 2.1.0

Engines. Most of this release is one theme: several of them were not playing
the game they claimed to, and the ones that were got slower the longer you
played.

### The engines got slower every move — they don't now

A fixed search depth costs whatever that depth costs in the position in front
of it. Measured with the built-in engine: 0.7s at the start of a game, 3-5s by
the middlegame, for the same nominal depth. Lynx, web Stockfish and Frozenight
were all driven that way and ignored the time budget the app handed them. They
now search by time, and the engines that cannot be interrupted mid-search
deepen one step at a time, checking the clock before starting a depth rather
than after.

Across a full round robin, every engine's median move time after move 20 is now
within a few percent of its median before move 10.

### The engine would stop moving a few turns in

The app thinks in the background while you do. When you moved, it asked for a
new move — and got the answer to the *previous* question, computed for a
position that no longer existed. That move was usually illegal, the board
rejected it, and the game sat on "thinking" for good. It showed up a few moves
in because that is when background thinking first outlasts a player's turn.

Searches are now serialised properly, and a move computed for an abandoned
search can never be returned for a new one. If an engine does answer with
something illegal, the app says so and hands the turn back instead of freezing.

### Frozenight could not play at all, and nobody had noticed

It applied none of the moves it was given, so it analysed the position the game
started from and answered for the wrong side. Once that was fixed it turned out
it could not castle either: it spoke castling in the internal
king-takes-rook form, which the board rejected as illegal. Both fixed. The
browser build of this engine had never been built at all — the file it loads
was missing from the app.

### Lc0 works, on every platform

It was a stub on desktop and mobile: selecting it gave you an engine that
reported an error. It now runs everywhere.

The weights it downloads were also broken — they returned nonsense for any
input, so it played nonsense. They have been re-exported from the original
Maia networks; Maia-1500 now opens 1.e4 and 1.d4 as it should. And the search
above them was not searching: it expanded the first move and then spent its
whole budget scoring every line with the *starting* position's evaluation. It
searches now, and a mate at the end of a line is scored as a mate — it used to
be scored as a loss, so the engine avoided delivering it.

### Chess960: you can castle

The chess library the app is built on assumes the king starts on e1, so in a
shuffled position it offered no castling move at all and quietly ignored the
castling rights. Added.

### Lynx on the web is 10-15x faster

Its bundle had never been compiled ahead of time. A search that took 1.6s now
takes 0.1s, and it holds a 300ms move budget where it used to overshoot into
multiple seconds. Settings offers a choice: the fast build (~6MB) or a small
one (~2MB) for slow connections.

### The app itself

Every screen redraw re-derived the move list and the game-over state by
replaying the whole game, and the clock made the screen redraw ten times a
second — so the app got heavier with every move played, and on the web that
came directly out of the engine's thinking time. Measured per redraw at move
23: 2.2ms, now 14µs.

Taking a move back used to leave the app describing a different game to the
engine than the one on the board, which is its own way of getting a nonsense
reply. Undo, PGN export and the move list now all follow the board.

### Fixed along the way

- Games that start from a position — Chess960, puzzles, a loaded FEN — were
  described to the engine as though they had started from the initial position.
- PGN export produced a file with no moves in it after a takeback.
- The move list showed PGN header tags as though they were moves after a
  takeback.
- The built-in engine could report "no legal moves" in a position that had
  plenty, when given very little time to think.
- Android release builds had been failing since before this release.
