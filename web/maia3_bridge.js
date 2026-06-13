// Maia3 bridge — loads onnxruntime-web UMD build + maia3-js for browser.
// MIT licensed.

let maia3Instance = null;
let maia3Loading = false;
let maia3Available = false;

async function maia3Load(variant, onProgress) {
  if (maia3Instance) return;
  if (maia3Loading) return;
  maia3Loading = true;

  try {
    // Step 1: Load ONNX Runtime Web (UMD build that works in browsers)
    if (typeof globalThis.ort === 'undefined') {
      console.log('[Maia3] Loading ONNX Runtime Web...');
      await loadScript('ort.min.js'); // bundled locally
      // Point WASM backend to CDN (avoids bundling 10-19MB WASM files)
      if (globalThis.ort && globalThis.ort.env) {
        globalThis.ort.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.3/dist/';
      }
      console.log('[Maia3] ONNX Runtime loaded');
    }

    // Step 2: Load maia3-js
    console.log('[Maia3] Loading maia3-js...');
    const module = await import('https://esm.sh/maia3-js@latest/web?external=onnxruntime-web');
    const Maia3 = module.Maia3 || module.default;

    if (!Maia3) {
      throw new Error('Could not find Maia3 class in module exports: ' + Object.keys(module));
    }

    maia3Instance = new Maia3({
      variant: variant || '5m',
      onProgress: (loaded, total) => {
        console.log(`[Maia3] Downloading model: ${Math.round(loaded/total*100)}%`);
      },
    });

    await maia3Instance.load();
    maia3Available = true;
    console.log('[Maia3] Ready (variant: ' + (variant || '5m') + ')');
  } catch (e) {
    console.error('[Maia3] Failed:', e.message || e);
    maia3Instance = null;
    maia3Available = false;
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

// Helper: load a script tag and wait for it
function loadScript(src) {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src="${src}"]`);
    if (existing) { resolve(); return; }
    const s = document.createElement('script');
    s.src = src;
    s.onload = resolve;
    s.onerror = () => reject(new Error('Failed to load: ' + src));
    document.head.appendChild(s);
  });
}

globalThis.maia3Load = maia3Load;
globalThis.maia3PredictMove = maia3PredictMove;
globalThis.maia3Close = maia3Close;
