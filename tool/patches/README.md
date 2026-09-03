# Patches against vendored engine source

`third_party/lynx-chess` is a working copy, cloned by
`scripts/build_lynx_wasm.sh` and gitignored, so changes made there are not
tracked by this repo. Anything that has to survive a re-clone lives here.

## `lynx-wasm-time-control.patch`

Lynx does not honour `movetime` under browser WASM. Measured in the tournament
harness: a median of 608 ms against a 300 ms budget, and one search that ran
past 40 s, which ends the game.

It is not a speed problem and not an AOT problem. Lynx enforces its hard limit
with `CancellationTokenSource.CancelAfter`, which schedules the cancellation on
a **timer** — and a timer callback needs a thread to run on. The search checks
its token at every node, so whenever that callback is late, the budget is not
enforced until the search ends on its own.

The patch adds `IsHardTimeLimitReached()` next to the stopwatch in
`Search/IDDFS.cs` and calls it from `NegaMax` and `QuiescenceSearch` every 2048
nodes, alongside the existing token check. Reading the clock depends on nothing
being scheduled, so it catches the cases the timer misses; where the timer does
fire it simply agrees with it. The cost is one `ElapsedMilliseconds` read every
few thousand nodes.

### What it measurably does, and what it does not

Ten warmed searches at a 300 ms budget, patched build against the shipped one,
same harness and positions, three repetitions:

```
                 median overshoot        p90 overshoot      worst
  patched          1.3-1.7x               1.9-2.5x          ~5.5s
  unpatched        1.8-2.8x               4.7-6.8x          ~6.7s
```

The patched build is consistently tighter, and it is the *non-AOT* build — a
slower engine per node, which should overshoot more, not less. So the effect is
real.

Two honest limits:

- **It does not remove the tail.** Roughly one search in ten still runs 5-6 s
  against a 300 ms budget, in both builds. Whatever causes that is not the
  cancellation path — most likely the runtime itself (GC, or tiering
  recompilation) stalling between node checks.
- **The 40 s search seen in the tournament does not reproduce here.** That run
  had eight engines playing concurrently on a loaded shared box, so CPU
  starvation is the more likely explanation for that particular number than
  anything in Lynx. An earlier version of this note asserted the timer "can
  never fire" in browser WASM; the A/B above shows the budget is partly
  enforced without the patch, so that claim was too strong.

The patch is cut against `CrispStrobe/lynx-chess` branch `wasm-browser`, which
is what `scripts/build_lynx_wasm.sh` clones.

**Don't build this on a dev box.** The AOT step peaked around 950 MB here
(clang plus MSBuild) and took a shared 7.7 GB machine to the OOM cliff, where
the kernel's victim is whichever process has the largest RSS — on a box full of
agent sessions, that is somebody's conversation, not your build. Use CI:

```
gh workflow run "Lynx WASM bundle"
```

`.github/workflows/lynx-wasm.yml` clones the fork, applies this patch, builds
with .NET 10 + `wasm-tools` (so AOT actually runs rather than silently falling
back), checks the bundle's files are present and non-empty, drives the engine
through `tool/uci/lynx_wasm_uci.mjs` for a `uciok`/`readyok`/`bestmove` round
trip, and opens a PR with the result. Inputs let you pick the Lynx ref, skip
the patch, or take the artifact without a PR.

If you must build locally, gate it: require free RAM to cover the peak outright
when swap is exhausted (MemAvailable reads healthy at the cliff, and swap does
not free itself), and have the build kill itself rather than letting the kernel
choose.

### Not included here

That working copy also carries unrelated uncommitted edits that predate this
work — `global.json` moved to .NET 10, `#if !BROWSER_WASM` guards around the
online tablebase prober and a `#if !DEBUG` block, and `Utils.cs` clamping NPS
through `long.MaxValue` rather than `ulong.MaxValue`. They are what makes the
WASM build work at all. They belong in the Lynx fork rather than in a patch
file, and are listed here only so nobody mistakes them for part of this fix.
