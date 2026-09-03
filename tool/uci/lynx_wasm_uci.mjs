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
      emit(line.startsWith('go')
          ? await interop.SendSearchCommand(line)
          : await interop.SendCommand(line));
    } catch (e) {
      process.stderr.write(`error handling "${line}": ${e}\n`);
    }
  });
});
// stdin closing must not cut a search short: queue the exit behind whatever is
// still running, or a piped script loses the reply to its last command.
rl.on('close', () => run(async () => process.exit(0)));
