// Maia3 bridge — uses locally bundled maia3-bundle.js + ort.min.js
// No CDN dependencies at runtime.

let maia3Instance = null;
let maia3Loading = false;

async function maia3Load(variant, onProgress) {
  if (maia3Instance) return;
  if (maia3Loading) return;
  maia3Loading = true;

  try {
    // ort.min.js is loaded via <script> tag in index.html
    // It sets globalThis.ort which maia3-bundle.js uses
    if (typeof globalThis.ort === 'undefined') {
      throw new Error('ONNX Runtime not loaded — check ort.min.js in index.html');
    }

    // Configure ONNX Runtime for browser (single-threaded, CDN WASM)
    if (globalThis.ort.env) {
      globalThis.ort.env.wasm.numThreads = 1; // No SharedArrayBuffer without COOP/COEP
      globalThis.ort.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/';
    }

    // maia3-bundle.js is loaded via <script> tag — sets globalThis.Maia3Class
    if (typeof globalThis.Maia3Class === 'undefined') {
      throw new Error('Maia3 bundle not loaded — check maia3-bundle.js in index.html');
    }

    console.log('[Maia3] Creating instance (variant: ' + (variant || '5m') + ')');
    maia3Instance = new globalThis.Maia3Class({
      variant: variant || '5m',
      onProgress: (loaded, total) => {
        console.log('[Maia3] Model: ' + Math.round(loaded / total * 100) + '%');
      },
    });

    await maia3Instance.load();
    console.log('[Maia3] Ready');
  } catch (e) {
    console.error('[Maia3] Failed:', e.message || e);
    maia3Instance = null;
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
    await maia3Instance.close();
    maia3Instance = null;
  }
}

globalThis.maia3Load = maia3Load;
globalThis.maia3PredictMove = maia3PredictMove;
globalThis.maia3Close = maia3Close;
