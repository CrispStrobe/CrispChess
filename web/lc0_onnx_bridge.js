// Thin ONNX bridge for Lc0 Dart engine.
// Handles ONNX Runtime Web session management + inference.
// Board encoding and MCTS are done in Dart.
//
// Converted Maia/lc0 ONNX models output:
//   policy: [batch, 1858]
//   wdl:    [batch, 3] (win, draw, loss probabilities)
//
// The leela2onnx export already emits policy logits in vocabulary order.

let lc0OnnxSession = null;

async function lc0OnnxLoad(modelUrl) {
  await lc0OnnxClose();

  // (Maia3 used to share ONNX Runtime here and its sessions had to be closed
  // first to avoid memory conflicts. It now runs on the pure-Dart interpreter
  // and never touches this runtime, so Lc0 is the only user.)

  // Lazy-load ONNX Runtime if not yet loaded
  if (typeof globalThis.ort === 'undefined') {
    if (typeof window._loadOrt === 'function') {
      await window._loadOrt();
    }
    if (typeof globalThis.ort === 'undefined') {
      throw new Error('ONNX Runtime not loaded');
    }
  }

  if (globalThis.ort.env) {
    globalThis.ort.env.wasm.numThreads = 1;
    globalThis.ort.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.21.0/dist/';
  }

  console.log('[Lc0ONNX] Loading model from: ' + modelUrl);

  let modelBytes;
  try {
    const cache = await caches.open('lc0-models');
    const cached = await cache.match(modelUrl);
    if (cached) {
      console.log('[Lc0ONNX] Found in cache');
      modelBytes = new Uint8Array(await cached.arrayBuffer());
    } else {
      console.log('[Lc0ONNX] Downloading...');
      const response = await fetch(modelUrl);
      if (!response.ok) throw new Error('HTTP ' + response.status);
      const cloned = response.clone();
      modelBytes = new Uint8Array(await response.arrayBuffer());
      try { await cache.put(modelUrl, cloned); } catch(_) {}
      console.log('[Lc0ONNX] Downloaded (' + modelBytes.length + ' bytes)');
    }
  } catch (e) {
    console.log('[Lc0ONNX] Cache unavailable: ' + e);
    const response = await fetch(modelUrl);
    modelBytes = new Uint8Array(await response.arrayBuffer());
  }

  lc0OnnxSession = await globalThis.ort.InferenceSession.create(
    modelBytes.buffer,
    { executionProviders: ['wasm'] }
  );
  console.log('[Lc0ONNX] Session ready');
  console.log('[Lc0ONNX] Inputs:', lc0OnnxSession.inputNames);
  console.log('[Lc0ONNX] Outputs:', lc0OnnxSession.outputNames);
}

// Takes a Float32Array of batch*7168 (112*8*8).
// Returns batch consecutive blocks of [policy(1858), wdl(3)].
async function lc0OnnxInfer(inputPlanes) {
  if (!lc0OnnxSession) throw new Error('Lc0 model not loaded');

  const ort = globalThis.ort;
  const sampleSize = 112 * 8 * 8;
  const batch = inputPlanes.length / sampleSize;
  if (!Number.isInteger(batch) || batch < 1) {
    throw new Error('Invalid Lc0 input length ' + inputPlanes.length);
  }
  const inputTensor = new ort.Tensor(
    'float32', inputPlanes, [batch, 112, 8, 8]);

  const inputName = lc0OnnxSession.inputNames[0];
  const feeds = {};
  feeds[inputName] = inputTensor;

  const result = await lc0OnnxSession.run(feeds);

  const outputNames = lc0OnnxSession.outputNames;
  let policyData, wdlData;

  // lc0's own exporter (`lc0 leela2onnx`) emits /output/policy already in
  // move-vocabulary order (1858) and /output/wdl already as a distribution, so
  // there is nothing to remap. Identify them by size.
  for (const name of outputNames) {
    const data = result[name].data;
    if (data.length === batch * 3) {
      wdlData = data;
    } else {
      policyData = data;
    }
  }

  if (!policyData) throw new Error('No policy output found');
  if (policyData.length !== batch * 1858) {
    throw new Error('Unexpected policy width ' + policyData.length +
      ' — expected ' + (batch * 1858) + ' from a leela2onnx export');
  }
  if (!wdlData) {
    wdlData = new Float32Array(batch * 3);
    for (let i = 0; i < batch; i++) {
      wdlData.set([0.33, 0.34, 0.33], i * 3);
    }
  }

  const combined = new Float32Array(batch * (1858 + 3));
  for (let i = 0; i < batch; i++) {
    const offset = i * 1861;
    combined.set(policyData.subarray(i * 1858, (i + 1) * 1858), offset);
    combined.set(wdlData.subarray(i * 3, (i + 1) * 3), offset + 1858);
  }
  return combined;
}

async function lc0OnnxClose() {
  if (lc0OnnxSession) {
    try { await lc0OnnxSession.release(); } catch(e) {
      console.warn('[Lc0ONNX] Release error:', e);
    }
    lc0OnnxSession = null;
  }
}

globalThis.lc0OnnxLoad = lc0OnnxLoad;
globalThis.lc0OnnxInfer = lc0OnnxInfer;
globalThis.lc0OnnxClose = lc0OnnxClose;
