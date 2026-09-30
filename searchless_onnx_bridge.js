// ONNX Runtime Web bridge for the searchless-chess transformers.
// Tokenization, move choice and repetition rules stay in Dart; this only
// holds the session and runs the batch. Sessions are keyed, so the 9M model
// can coexist with anything else using ONNX Runtime Web.

const searchlessSessions = {};

async function searchlessOnnxLoad(key, modelUrl) {
  if (searchlessSessions[key]) return;
  if (typeof globalThis.ort === 'undefined' && typeof window._loadOrt === 'function') {
    await window._loadOrt();
  }
  if (typeof globalThis.ort === 'undefined') throw new Error('ONNX Runtime not loaded');
  if (globalThis.ort.env) {
    globalThis.ort.env.wasm.numThreads = 1; // no cross-origin isolation here
    if (typeof resolveWasmPaths === 'function') {
      globalThis.ort.env.wasm.wasmPaths = await resolveWasmPaths(); // lc0_onnx_bridge.js
    }
  }
  let bytes;
  try {
    const cache = await caches.open('searchless-models');
    const hit = await cache.match(modelUrl);
    if (hit) {
      bytes = new Uint8Array(await hit.arrayBuffer());
    } else {
      const response = await fetch(modelUrl);
      if (!response.ok) throw new Error('HTTP ' + response.status);
      const copy = response.clone();
      bytes = new Uint8Array(await response.arrayBuffer());
      try { await cache.put(modelUrl, copy); } catch (_) {}
    }
  } catch (e) {
    const response = await fetch(modelUrl);
    bytes = new Uint8Array(await response.arrayBuffer());
  }
  searchlessSessions[key] = await globalThis.ort.InferenceSession.create(
    bytes.buffer, { executionProviders: ['wasm'] });
  console.log('[Searchless] ' + key + ' ready (ONNX Runtime Web)');
}

// tokens: Int32Array of rows * 79. Returns Float32Array of rows * 128.
async function searchlessOnnxInfer(key, tokens, rows) {
  const session = searchlessSessions[key];
  if (!session) throw new Error('Searchless model ' + key + ' not loaded');
  const ort = globalThis.ort;
  const ids = BigInt64Array.from(tokens, (x) => BigInt(x));
  const result = await session.run({ tokens: new ort.Tensor('int64', ids, [rows, 79]) });
  return result.log_probs.data;
}

async function searchlessOnnxClose(key) {
  const session = searchlessSessions[key];
  delete searchlessSessions[key];
  if (session && session.release) await session.release();
}
