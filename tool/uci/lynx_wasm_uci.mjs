#!/usr/bin/env node
// Lynx WASM as an ordinary UCI engine on stdin/stdout.
//
//   node tool/uci/lynx_wasm_uci.mjs
//
// The Dart engine class for this build talks to the browser through
// `dart:js_interop`, so it cannot run outside one. The engine itself is just
// .NET compiled to WASM and the Mono runtime works fine under Node, so wrapping
// it as a UCI process makes the *same* engine usable from the command line —
// and from anything that speaks UCI, including this repo's own
// GenericUciEngine and the tournament harness.
//
// Requires the WASM build in web/lynx/_framework (scripts/build_lynx_wasm.sh).
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { existsSync } from 'node:fs';

const here = dirname(fileURLToPath(import.meta.url));
const framework = join(here, '..', '..', 'web', 'lynx', '_framework', 'dotnet.js');

if (!existsSync(framework)) {
  process.stderr.write(
    `Lynx WASM build not found at ${framework}\n` +
    'Run scripts/build_lynx_wasm.sh first.\n');
  process.exit(1);
}

const { dotnet } = await import(framework);
const { getAssemblyExports, getConfig } = await dotnet
  .withDiagnosticTracing(false)
  .create();
const exports = await getAssemblyExports(getConfig().mainAssemblyName);
const interop = exports.LynxWasm.UciInterop;

const init = await interop.Initialize();
if (init !== 'ok') {
  process.stderr.write(`Lynx WASM failed to initialise: ${init}\n`);
  process.exit(1);
}

// Mono tiers up as it runs: the first search of a session reaches depth 1 where
// a warmed-up one reaches depth 8 in the same second. The app pays this cost
// while it shows "Loading"; do the same here so a CLI run measures the engine
// rather than its cold start.
await interop.SendCommand('position startpos');
await interop.SendSearchCommand('go movetime 600');

// A move costs a fixed amount outside the search — dispatching into Mono and
// back — and Lynx's own MoveOverhead option does not pay for it: sweeping that
// from 50 to 450 moved the median move time by three milliseconds, while the
// time actually requested tracked it one for one. Measured on a CI runner at
// four budgets, the gap was 57, 55, 57 and 56ms: a constant, not a fraction.
//
// So the fix is to ask for that much less. The size of it is learned rather
// than hardcoded, because it is a property of the machine — a phone and a CI
// runner will not agree on it — and it starts at zero so the first move
// behaves exactly as before and every later one is corrected.
let overheadMs = 0;

/// When the caller started paying for the next move.
///
/// A move costs the caller more than the search. Every command is its own trip
/// into Mono, and a GUI asking for a move sends several back to back —
/// `setoption`, then `position`, then `go` — while its clock runs from the
/// first of them. Timing only the `go` learned an overhead of 5ms where the
/// caller saw 50; timing from `position` closed most of it and left the
/// `setoption` trip outside, which is the 52ms between a probe that sends two
/// commands and a round robin that sends three.
///
/// So the clock starts at whichever of them arrives first and stops when the
/// search answers.
let moveStartedAt = null;

function budgetOf(command) {
  const m = /\bmovetime\s+(\d+)/.exec(command);
  return m ? Number(m[1]) : null;
}

/// Ask for `movetime` minus the measured overhead, never less than half.
function discount(command) {
  const asked = budgetOf(command);
  if (asked === null) return command;
  const want = Math.max(Math.round(asked / 2), Math.round(asked - overheadMs));
  return command.replace(/\bmovetime\s+\d+/, `movetime ${want}`);
}

function observe(asked, actual) {
  const want = Math.max(Math.round(asked / 2), Math.round(asked - overheadMs));
  const seen = actual - want;
  // Half the budget is the limit worth following: the discount never goes
  // below half anyway, so a larger reading cannot be acted on and most likely
  // means the clock started somewhere it should not have. A third was too
  // tight — three trips into Mono measured 108ms against a 300ms budget, the
  // real cost, and rejecting it left the overshoot in place.
  if (seen > 0 && seen < asked / 2) {
    overheadMs = overheadMs === 0 ? seen : 0.5 * overheadMs + 0.5 * seen;
  }
}

function emit(text) {
  if (!text) return;
  for (const line of String(text).split('\n')) {
    if (line.trim()) process.stdout.write(`${line.trim()}\n`);
  }
}

// The Mono search runs to completion in one call, so commands are handled one
// at a time. A GUI that sends `stop` mid-search will simply see the search
// finish on its own — the same behaviour the browser build has.
let chain = Promise.resolve();
const run = (fn) => (chain = chain.then(fn, fn));

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on('line', (raw) => {
  const line = raw.trim();
  if (!line) return;
  if (line === 'quit') {
    run(async () => process.exit(0));
    return;
  }
  run(async () => {
    try {
      // `go` blocks until the search ends and returns every info line plus the
      // bestmove; everything else is a plain command/response.
      if (line.startsWith('go')) {
        const started = moveStartedAt ?? Date.now();
        moveStartedAt = null;
        const asked = budgetOf(line);
        const sent = discount(line);
        emit(await interop.SendSearchCommand(sent));
        const took = Date.now() - started;
        if (asked !== null) observe(asked, took);
        if (process.env.LYNX_TRACE) {
          process.stderr.write(
            `[lynx] asked ${asked} sent "${sent}" took ${took}ms ` +
            `overhead now ${Math.round(overheadMs)}ms\n`);
        }
      } else {
        // `ucinewgame` and `isready` are housekeeping between moves, not part
        // of one, so they do not start the clock.
        if ((line.startsWith('position') || line.startsWith('setoption')) &&
            moveStartedAt === null) {
          moveStartedAt = Date.now();
        }
        emit(await interop.SendCommand(line));
      }
    } catch (e) {
      process.stderr.write(`error handling "${line}": ${e}\n`);
    }
  });
});
// stdin closing must not cut a search short: queue the exit behind whatever is
// still running, or a piped script loses the reply to its last command.
rl.on('close', () => run(async () => process.exit(0)));
