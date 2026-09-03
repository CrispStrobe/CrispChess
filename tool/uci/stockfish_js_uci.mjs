#!/usr/bin/env node
// Stockfish.js as an ordinary UCI engine on stdin/stdout.
//
//   node tool/uci/stockfish_js_uci.mjs [sf10|sf18asm]
//
// The web build drives stockfish.js from a Web Worker through
// `dart:js_interop`, which only exists in a browser. The engine is plain
// JS/WASM though, and Node's worker_threads runs it unchanged — so this makes
// the *same* engine usable from the command line and from anything that speaks
// UCI, this repo's GenericUciEngine and tournament harness included.
//
// GPL-3.0: stockfish.js is downloaded at run time, exactly as the app does it,
// and is never bundled here.
import { Worker } from 'node:worker_threads';
import { createInterface } from 'node:readline';
import { mkdirSync, existsSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const VARIANTS = {
  sf10: {
    url: 'https://cdn.jsdelivr.net/npm/stockfish.js@10.0.2/stockfish.js',
    file: 'stockfish-10.js',
  },
  sf18asm: {
    url: 'https://huggingface.co/cstr/stockfish-js-wasm/resolve/main/stockfish-18-asm.js',
    file: 'stockfish-18-asm.js',
  },
};

const variant = VARIANTS[process.argv[2] ?? 'sf10'];
if (!variant) {
  process.stderr.write(`unknown variant; expected one of ${Object.keys(VARIANTS).join(', ')}\n`);
  process.exit(1);
}

// Same cache location the Lynx download uses, so a CLI run and the app's own
// downloads sit together.
const dir = join(homedir(), '.crispchess', 'engines', 'stockfish-js');
const path = join(dir, variant.file);

if (!existsSync(path)) {
  process.stderr.write(`downloading ${variant.url}\n`);
  const response = await fetch(variant.url);
  if (!response.ok) {
    process.stderr.write(`download failed: ${response.status} ${response.statusText}\n`);
    process.exit(1);
  }
  mkdirSync(dir, { recursive: true });
  writeFileSync(path, Buffer.from(await response.arrayBuffer()));
}

// stockfish.js is a Web Worker script, not a Node module — it needs a handful
// of browser globals before it will even start. See _web_worker_shim.cjs.
const shim = join(dirname(fileURLToPath(import.meta.url)), '_web_worker_shim.cjs');
const worker = new Worker(shim, { workerData: { path } });
worker.on('message', (msg) => process.stdout.write(`${msg}\n`));
worker.on('error', (e) => {
  process.stderr.write(`stockfish.js error: ${e}\n`);
  process.exit(1);
});

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on('line', (raw) => {
  const line = raw.trim();
  if (!line) return;
  worker.postMessage(line);
  if (line === 'quit') {
    // Give the worker a moment to shut down cleanly.
    setTimeout(() => process.exit(0), 100);
  }
});
// Don't exit the moment a piped script's stdin ends — the engine may still be
// searching, and its `bestmove` is the whole point.
rl.on('close', () => {});
