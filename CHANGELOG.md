# Changelog

## Unreleased

### Engines now spend the time they are given

Four of them were not, in two different ways, and the round robin's latency
table is where it showed: every engine sat at a `late/opening` ratio of 1.00
except the ones with something wrong.

Frozenight finished searching before its clock ran out. Depth is the
difficulty setting, and at full strength the ceiling was low enough to stop
the search first — 830 of its 1554 moves ended at depth 14 with most of the
budget unspent, several of them in three milliseconds. The built-in engine did
the same in endgames, where ten plies is cheap: 149ms of a 300ms budget,
handing back half the clock in exactly the positions where another ply is
worth most. Both now stop when the time does.

Lynx did the opposite. On the web it took 408ms of a 300ms budget — time its
opponents did not get — because a move costs more than its search: setting the
position is its own trip into the .NET runtime, and that was not being counted.
It now measures the whole move and asks for correspondingly less, landing on
300ms. The desktop build had the reverse problem, reserving 50ms of every move
against losing on time in an app where every move has its own budget and there
is no clock to run out; that reserve is now 10ms.

A search that cannot be interrupted is bounded by a node count instead of a
guess about how long the next depth will take. That guess was wrong in
endgames, where iterations stay cheap for many plies and then one explodes:
two games were abandoned after an engine stopped answering. Frozenight's worst
move fell from 1111ms to 331ms of a 300ms budget as a result.

### A crashed engine no longer ends the game

Nothing watched the engine process. When one exited mid-search, nothing
completed the request: the app waited out its own timeout and reported a slow
engine, leaving the dead process in place so every later move failed the same
way until you noticed and switched engines by hand, mid-game.

A death is now noticed in milliseconds rather than seconds, reported with what
the engine printed as it went, and recovered from — the app starts a
replacement and asks it for the move. An engine that keeps dying is not
restarted forever.

Failures also say what kind they are, so a crash being recovered from reads
differently from one that needs you to pick another engine, and analysis
trouble no longer looks like trouble with the game.

### Analysis was running unbounded

The eval bar asked for a fixed depth with no clock behind it — the thing taken
out of ordinary play because a fixed depth costs whatever that depth costs in
the position in front of it. Nothing stopped it either, so a strong engine sat
at full CPU until your next move happened to interrupt it. On a phone that is
the battery. It is bounded now.

Analysis failures were also invisible on the web: two engines caught them,
wrote to a console nobody has open, and let the eval bar quietly stop updating.

### Lc0 is faster, and the web download is half the size

The engine evaluates two positions per batch rather than four and uses half the
machine's cores rather than all of them — both measured, and both the opposite
of what it was doing: four threads and a batch of four came to 1.33ms per
position against 0.74ms. That is 405 positions inside a 300ms move budget where
there were 225.

On the web it was downloading the WebGPU build of its runtime, 23MB, on a page
that cannot use WebGPU — 11MB of binary that could never be reached. It now
takes the 12MB one, served from the app rather than a public CDN, so a blocked
or unreachable CDN no longer stops the engine before it can say why.

Linux desktop builds now ship the native runtime they were missing, which they
had been silently falling back from onto a five-times slower one.

### Lc0 was not playing the game it was given

The engine scored zero out of twenty-four in the strength tournament while
making reasonable-looking moves in every position anyone spot-checked. Both
things were true, and for the same reason: the checks people run are opening
positions, and the opening position is where each of these is invisible.

Found by comparing against lc0 itself — the input planes against its encoder,
the policy against its own network output, and finally by playing it. The
harness lives in `tool/oracle/` and runs in CI.

- Two of the network's input planes were wrong. Castling rights had kingside
  and queenside swapped, for both sides; in the start position all four rights
  are set, so all four planes look identical either way. The rule-50 counter
  was divided by 100 — a scale that belongs to a different lc0 input format —
  so the network saw 0.16 where it expected 16.
- The history planes were built from every *other* ply. They were accumulated
  when the engine was asked to move, and that only happens on its own turns,
  so the network was shown a game in which the opponent never moved.
- Positions inside the search were described with the history of the position
  the search started from, so a line three moves deep was presented as a
  different game.
- One simulation used to be worse than none: the first one scored every move
  identically and picked whichever the move generator produced first, which is
  a2a3 from the start position.
- On the web, the value head had a softmax applied to numbers that were
  already probabilities, which squeezed the evaluation from ±1 into about
  ±0.36 and left the search close to value-blind.

Against lc0 on the same weights, the engine now picks the same move in 40 of
40 test positions, and its policy agrees to within 0.06%.

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
