// Thin ONNX bridge for Lc0 Dart engine.
// Handles ONNX Runtime Web session management + inference.
// Board encoding and MCTS are done in Dart.
//
// Converted Maia/lc0 ONNX models output:
//   pol_flat: [1, 5120] (80x64 spatial convolutional policy)
//   wdl:      [1, 3]    (win, draw, loss probabilities)
//
// This bridge applies kConvPolicyMap to extract 1858 policy logits
// from the 5120 spatial output.

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

// Takes Float32Array of 7168 (112*8*8).
// Returns Float32Array of 1861: [policy(1858), wdl(3)].
async function lc0OnnxInfer(inputPlanes) {
  if (!lc0OnnxSession) throw new Error('Lc0 model not loaded');

  const ort = globalThis.ort;
  const inputTensor = new ort.Tensor('float32', inputPlanes, [1, 112, 8, 8]);

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
    if (data.length === 3) {
      wdlData = data;
    } else {
      policyData = data;
    }
  }

  if (!policyData) throw new Error('No policy output found');
  if (policyData.length !== 1858) {
    throw new Error('Unexpected policy width ' + policyData.length +
      ' — expected 1858 from a leela2onnx export');
  }
  if (!wdlData) wdlData = new Float32Array([0.33, 0.34, 0.33]);

  const combined = new Float32Array(1858 + 3);
  combined.set(policyData, 0);
  combined.set(wdlData, 1858);
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
