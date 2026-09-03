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
a **timer**. A timer callback needs a thread to run on, and in single-threaded
browser WASM the synchronous search owns the only one — so the token is never
cancelled until the search it was meant to interrupt has already finished. The
search checks that token at every node, and the token is never set.

The patch adds `IsHardTimeLimitReached()` next to the stopwatch in
`Search/IDDFS.cs` and calls it from `NegaMax` and `QuiescenceSearch` every 2048
nodes, alongside the existing token check. Reading the clock depends on nothing
being scheduled, so it works where the timer cannot; on platforms where the
timer does fire it simply agrees with it. The cost is one `ElapsedMilliseconds`
read every few thousand nodes.

To apply:

```sh
cd third_party/lynx-chess
git apply ../../tool/patches/lynx-wasm-time-control.patch
```

Then rebuild the bundle with `scripts/build_lynx_wasm.sh`. **The AOT build is
memory-hungry** — it peaked at ~950 MB here (clang plus MSBuild) and pushed a
7.7 GB shared box to the OOM cliff. Build it somewhere with room, or gate it:
see `safe_lynx_verify.sh` in the session scratchpad for the shape (require free
RAM to cover the peak outright when swap is exhausted, and have the build kill
itself rather than letting the kernel choose a victim).

### Not included here

That working copy also carries unrelated uncommitted edits that predate this
work — `global.json` moved to .NET 10, `#if !BROWSER_WASM` guards around the
online tablebase prober and a `#if !DEBUG` block, and `Utils.cs` clamping NPS
through `long.MaxValue` rather than `ulong.MaxValue`. They are what makes the
WASM build work at all. They belong in the Lynx fork rather than in a patch
file, and are listed here only so nobody mistakes them for part of this fix.
