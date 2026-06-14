// Maia3 bridge — uses locally bundled maia3-bundle.js + ort.min.js
// No CDN dependencies at runtime.

let maia3Instance = null;
let maia3Loading = false;
let maia3CurrentVariant = null;

async function maia3Load(variant, onProgress) {
  // If already loaded with same variant, skip
  if (maia3Instance && maia3CurrentVariant === variant) return;

  // Close any existing sessions (both bridges share ONNX Runtime)
  await maia3Close();
  if (typeof globalThis.maia3OnnxClose === 'function') {
    try { await globalThis.maia3OnnxClose(); } catch(_) {}
  }

  if (maia3Loading) return;
  maia3Loading = true;

  try {
    if (typeof globalThis.ort === 'undefined') {
      throw new Error('ONNX Runtime not loaded — check ort.min.js in index.html');
    }

    // Configure ONNX Runtime for browser
    // Use webgl backend to avoid WASM memory conflict with Flutter WASM
    if (globalThis.ort.env) {
      globalThis.ort.env.wasm.numThreads = 1;
      globalThis.ort.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/';
    }

    if (typeof globalThis.Maia3Class === 'undefined') {
      throw new Error('Maia3 bundle not loaded — check maia3-bundle.js in index.html');
    }

    var v = variant || '5m';
    console.log('[Maia3] Creating instance (variant: ' + v + ')');
    maia3Instance = new globalThis.Maia3Class({
      variant: v,
      // Use wasm backend (webgl doesn't support int64 tensors needed for ELO inputs)
      executionProviders: ['wasm'],
      onProgress: (loaded, total) => {
        console.log('[Maia3] Model: ' + Math.round(loaded / total * 100) + '%');
      },
    });

    await maia3Instance.load();
    maia3CurrentVariant = v;
    console.log('[Maia3] Ready (variant: ' + v + ')');
  } catch (e) {
    console.error('[Maia3] Failed:', e.message || e);
    maia3Instance = null;
    maia3CurrentVariant = null;
    throw e;
  } finally {
    maia3Loading = false;
  }
}

async function maia3PredictMove(fen, selfElo) {
  if (!maia3Instance) throw new Error('Maia3 not loaded');
  const result = await maia3Instance.predict({ fen, selfElo: selfElo || 1500 });
  return result.bestMove;
}

async function maia3Close() {
  if (maia3Instance) {
    try { await maia3Instance.close(); } catch(e) {
      console.warn('[Maia3] Close error:', e);
    }
    maia3Instance = null;
    maia3CurrentVariant = null;
  }
}

globalThis.maia3Load = maia3Load;
globalThis.maia3PredictMove = maia3PredictMove;
globalThis.maia3Close = maia3Close;
