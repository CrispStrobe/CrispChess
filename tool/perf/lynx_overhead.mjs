#!/usr/bin/env node
// What MoveOverhead does Lynx WASM need to land on its move budget?
//
//   node tool/perf/lynx_overhead.mjs [--budget 300] [--values 50,150,250]
//
// Lynx aims to finish a move in (budget - MoveOverhead) and the option exists
// precisely to pay for whatever happens outside the search. On the native
// build the default of 50 is right: a 300ms budget comes back in 251ms. The
// WASM build overshoots the same target badly — 408ms measured over a round
// robin — because Mono notices the deadline late, so it needs a larger
// allowance, and the only way to know how much is to measure it.
//
// Every value is measured in ONE process, after one warm-up, for the same
// reason the inference benchmark sweeps its parameters in one run: Mono tiers
// up as it goes and a fresh process costs seconds, so comparing a number from
// one process against a number from another measures the start-up, not the
// option.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
};

const budget = Number(arg('budget', '300'));
const values = arg('values', '50,150,250,350').split(',').map(Number);

// A spread of positions rather than one: the overshoot depends on how long the
// final iteration runs, which depends on the position.
const POSITIONS = [
  '',
  'e2e4 e7e5 g1f3 b8c6 f1b5 a7a6',
  'd2d4 g8f6 c2c4 e7e6 b1c3 f8b4 e2e3 e8g8 f1d3 d7d5',
  'e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6 f1e2 e7e5',
  'd2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 d5c4 a2a4 c8f5 e2e3 e7e6 f1c4 f8b4',
];

const child = spawn('node', [join(root, 'tool', 'uci', 'lynx_wasm_uci.mjs')], {
  stdio: ['pipe', 'pipe', 'ignore'],
});
const rl = createInterface({ input: child.stdout, terminal: false });

let waiting = null;
rl.on('line', (line) => {
  if (waiting && waiting.test(line)) {
    const resolve = waiting.resolve;
    waiting = null;
    resolve(line);
  }
});

const send = (line) => child.stdin.write(`${line}\n`);
const until = (test) =>
  new Promise((resolve) => {
    waiting = { test, resolve };
  });

const ready = () => {
  send('isready');
  return until((l) => l.trim() === 'readyok');
};

const move = async (moves) => {
  send(`position startpos${moves ? ` moves ${moves}` : ''}`);
  const started = Date.now();
  send(`go movetime ${budget}`);
  await until((l) => l.startsWith('bestmove'));
  return Date.now() - started;
};

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

send('uci');
await until((l) => l.trim() === 'uciok');
await ready();

// Mono tiers up as it runs; measure a warmed engine, not its first minute.
for (const moves of POSITIONS) await move(moves);
for (const moves of POSITIONS) await move(moves);

console.log(`budget ${budget}ms, ${POSITIONS.length} positions per value\n`);
console.log(`${'MoveOverhead'.padStart(13)}${'median'.padStart(10)}` +
  `${'max'.padStart(8)}${'vs budget'.padStart(12)}`);

const results = [];
for (const value of values) {
  send(`setoption name MoveOverhead value ${value}`);
  await ready();
  const times = [];
  for (const moves of POSITIONS) times.push(await move(moves));
  const med = median(times);
  results.push({ value, med });
  const off = ((med - budget) / budget) * 100;
  console.log(`${String(value).padStart(13)}${`${med}ms`.padStart(10)}` +
    `${`${Math.max(...times)}ms`.padStart(8)}` +
    `${`${off >= 0 ? '+' : ''}${off.toFixed(0)}%`.padStart(12)}`);
}

const best = results.reduce((a, b) =>
  Math.abs(b.med - budget) < Math.abs(a.med - budget) ? b : a);
console.log(`\nclosest to the budget: MoveOverhead ${best.value} ` +
  `(${best.med}ms for ${budget}ms)`);

send('quit');
child.stdin.end();
setTimeout(() => process.exit(0), 500);
