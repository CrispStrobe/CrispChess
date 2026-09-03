#!/usr/bin/env node
// Frozenight WASM as an ordinary UCI engine on stdin/stdout.
//
//   node tool/uci/frozenight_wasm_uci.mjs
//
// Same idea as the other adapters: the Dart class for this build only runs in a
// browser, but the engine is a wasm-bindgen module and Node runs it unchanged.
//
// Requires the build in web/ (frozenight_wasm.js + frozenight_wasm_bg.wasm):
//   cd native/frozenight-wasm
//   cargo build --release --target wasm32-unknown-unknown
//   wasm-bindgen target/wasm32-unknown-unknown/release/frozenight_wasm.wasm \
//     --out-dir ../../web --target web
import { createInterface } from 'node:readline';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

const web = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'web');
const glue = join(web, 'frozenight_wasm.js');
const wasm = join(web, 'frozenight_wasm_bg.wasm');

if (!existsSync(glue) || !existsSync(wasm)) {
  process.stderr.write(
    `Frozenight WASM build not found in ${web}\n` +
    'See the header of this file for the two build commands.\n');
  process.exit(1);
}

// The wasm-bindgen `web` target fetches its .wasm by URL, which Node cannot do
// for a file path — hand it the bytes instead.
const { default: init, ...fz } = await import(pathToFileURL(glue).href);
await init({ module_or_path: await readFile(wasm) });
fz.init(16);

const say = (line) => process.stdout.write(`${line}\n`);

let position = { fen: 'startpos', moves: '' };

/// Iterative deepening inside a time budget. Each `search(d)` is one
/// uninterruptible WASM call, so the clock is checked *before* starting a
/// depth: checking afterwards puts no bound on the iteration that overshoots.
function go(command) {
  const depthMatch = /\bdepth\s+(\d+)/.exec(command);
  const timeMatch = /\bmovetime\s+(\d+)/.exec(command);
  const maxDepth = depthMatch ? Number(depthMatch[1]) : 14;
  const budgetMs = timeMatch ? Number(timeMatch[1]) : depthMatch ? 5000 : 1000;

  const started = Date.now();
  let best = null;
  for (let d = 1; d <= maxDepth; d++) {
    const elapsed = Date.now() - started;
    // Each iteration costs roughly 2.5x the whole search so far.
    if (d > 1 && elapsed * 2.5 >= budgetMs) break;
    const move = fz.search(d);
    if (move && move !== '0000') {
      best = move;
      say(`info depth ${d} time ${Date.now() - started} pv ${move}`);
    }
  }
  say(`bestmove ${best ?? '0000'}`);
}

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on('line', (raw) => {
  const line = raw.trim();
  if (!line) return;

  if (line === 'uci') {
    say('id name Frozenight WASM');
    say('id author Analog Hors');
    say('uciok');
  } else if (line === 'isready') {
    say('readyok');
  } else if (line === 'ucinewgame') {
    position = { fen: 'startpos', moves: '' };
  } else if (line.startsWith('position')) {
    const parts = line.split(/\s+/);
    const movesAt = parts.indexOf('moves');
    const fen = parts[1] === 'fen'
        ? parts.slice(2, movesAt > 0 ? movesAt : parts.length).join(' ')
        : 'startpos';
    position = {
      fen,
      moves: movesAt > 0 ? parts.slice(movesAt + 1).join(' ') : '',
    };
    fz.set_position(position.fen, position.moves);
  } else if (line.startsWith('go')) {
    go(line);
  } else if (line === 'quit') {
    process.exit(0);
  }
  // `stop` and `setoption` are accepted and ignored: the search is one
  // synchronous call and the engine exposes no options.
});
rl.on('close', () => process.exit(0));
