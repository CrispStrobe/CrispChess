// Runs a browser Web Worker script inside a Node worker thread.
//
// stockfish.js is an Emscripten build packaged as a Web Worker: it assigns a
// bare `onmessage`, calls `postMessage`, and reads `location.href` to find
// itself. None of that exists in Node's worker_threads, which is why loading it
// directly produced silence (and why scripts/test_stockfish_js.sh never
// actually worked). Providing the four globals it expects is enough.
//
// Entry point for a `new Worker(shim, { workerData: { path } })`.
const { parentPort, workerData } = require('node:worker_threads');
const { pathToFileURL } = require('node:url');

let handler = null;
Object.defineProperty(globalThis, 'onmessage', {
  configurable: true,
  get: () => handler,
  set: (fn) => {
    handler = fn;
  },
});

globalThis.self = globalThis;
globalThis.location = { href: pathToFileURL(workerData.path).href };
globalThis.postMessage = (message) => parentPort.postMessage(message);
globalThis.close = () => process.exit(0);
globalThis.importScripts = () => {};

parentPort.on('message', (message) => {
  if (handler) handler({ data: message });
});

require(workerData.path);
