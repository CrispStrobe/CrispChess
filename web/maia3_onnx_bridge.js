// Thin ONNX bridge for Maia3 Dart engine.
// Handles only raw session management + inference.
// Tokenization and sampling are done in Dart.

let maia3OnnxSession = null;

async function maia3OnnxLoad(modelUrl) {
  // Release any existing sessions (both bridges share ONNX Runtime)
  await maia3OnnxClose();
  if (typeof globalThis.maia3Close === 'function') {
    try { await globalThis.maia3Close(); } catch(_) {}
  }

  if (typeof globalThis.ort === 'undefined') {
    throw new Error('ONNX Runtime not loaded — check ort.min.js in index.html');
  }

  // Configure WASM — proxy=true runs ONNX in a Web Worker to avoid
  // memory conflicts with Flutter's own WASM runtime
  if (globalThis.ort.env) {
    globalThis.ort.env.wasm.numThreads = 1;
    globalThis.ort.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.21.0/dist/';
    globalThis.ort.env.wasm.proxy = true;
  }

  console.log('[Maia3ONNX] Loading model from: ' + modelUrl);

  // Try Cache Storage for the model
  let modelBytes;
  try {
    const cache = await caches.open('maia3-models');
    const cached = await cache.match(modelUrl);
    if (cached) {
      console.log('[Maia3ONNX] Found in cache');
      modelBytes = new Uint8Array(await cached.arrayBuffer());
    } else {
      console.log('[Maia3ONNX] Downloading...');
      const response = await fetch(modelUrl);
      if (!response.ok) throw new Error('HTTP ' + response.status);
      const cloned = response.clone();
      modelBytes = new Uint8Array(await response.arrayBuffer());
      try { await cache.put(modelUrl, cloned); } catch(_) {}
      console.log('[Maia3ONNX] Downloaded and cached (' + modelBytes.length + ' bytes)');
    }
  } catch (e) {
    console.log('[Maia3ONNX] Cache unavailable, fetching directly: ' + e);
    const response = await fetch(modelUrl);
    modelBytes = new Uint8Array(await response.arrayBuffer());
  }

  // Use wasm backend (webgl doesn't support int64 tensors needed for ELO inputs)
  maia3OnnxSession = await globalThis.ort.InferenceSession.create(
    modelBytes.buffer,
    { executionProviders: ['wasm'] }
  );
  console.log('[Maia3ONNX] Session ready');
}

// Returns a Float32Array of 4355 elements:
// [0..4351] = move logits, [4352..4354] = value logits (loss, draw, win)
async function maia3OnnxInfer(tokens, selfElo, oppoElo) {
  if (!maia3OnnxSession) throw new Error('Model not loaded');

  const ort = globalThis.ort;

  const tokensTensor = new ort.Tensor('float32', tokens, [1, 64, 96]);
  const selfEloTensor = new ort.Tensor('int64', BigInt64Array.from([BigInt(selfElo)]), [1]);
  const oppoEloTensor = new ort.Tensor('int64', BigInt64Array.from([BigInt(oppoElo)]), [1]);

  const feeds = {
    tokens: tokensTensor,
    self_elo: selfEloTensor,
    oppo_elo: oppoEloTensor,
  };

  const result = await maia3OnnxSession.run(feeds);

  const moveData = result.logits_move.data;
  const valueData = result.logits_value.data;
  const combined = new Float32Array(4352 + 3);
  combined.set(moveData, 0);
  combined.set(valueData, 4352);
  return combined;
}

async function maia3OnnxClose() {
  if (maia3OnnxSession) {
    try { await maia3OnnxSession.release(); } catch(e) {
      console.warn('[Maia3ONNX] Release error:', e);
    }
    maia3OnnxSession = null;
  }
}

globalThis.maia3OnnxLoad = maia3OnnxLoad;
globalThis.maia3OnnxInfer = maia3OnnxInfer;
globalThis.maia3OnnxClose = maia3OnnxClose;
