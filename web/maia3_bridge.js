// Bridge between Dart and maia3-js on web.
// MIT licensed neural network chess engine.

let maia3Instance = null;
let maia3Loading = false;

async function maia3Load(variant, onProgress) {
  if (maia3Instance) return;
  if (maia3Loading) return;
  maia3Loading = true;

  try {
    // Configure ONNX Runtime WASM paths before importing maia3
    // This prevents the "module.require is not implemented" error
    if (typeof globalThis.ort === 'undefined') {
      // Load ONNX Runtime Web first
      const ortModule = await import('https://esm.sh/onnxruntime-web@1.20.1');
      globalThis.ort = ortModule;

      // Set WASM paths to CDN
      if (ortModule.env && ortModule.env.wasm) {
        ortModule.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/';
      }
    }

    // Now import maia3-js
    const maia3Module = await import('https://esm.sh/maia3-js@latest/web?external=onnxruntime-web');
    const Maia3 = maia3Module.Maia3 || maia3Module.default?.Maia3;

    if (!Maia3) {
      throw new Error('Maia3 class not found in module');
    }

    maia3Instance = new Maia3({
      variant: variant || '5m',
      onProgress: (loaded, total) => {
        if (onProgress) onProgress(loaded, total);
        console.log(`[Maia3] Loading: ${Math.round(loaded/total*100)}%`);
      },
    });

    await maia3Instance.load();
    console.log('[Maia3] Model loaded:', variant);
  } catch (e) {
    console.error('[Maia3] Failed to load:', e);
    maia3Instance = null;
    throw e;
  } finally {
    maia3Loading = false;
  }
}

async function maia3Predict(fen, selfElo, oppoElo, priorFens) {
  if (!maia3Instance) throw new Error('Maia3 not loaded');
  const input = { fen, selfElo: selfElo || 1500 };
  if (oppoElo) input.oppoElo = oppoElo;
  if (priorFens && priorFens.length > 0) input.priorFens = priorFens;
  return await maia3Instance.predict(input);
}

async function maia3PredictMove(fen, selfElo) {
  const result = await maia3Predict(fen, selfElo);
  return result.bestMove;
}

async function maia3Close() {
  if (maia3Instance) {
    await maia3Instance.close();
    maia3Instance = null;
  }
}

globalThis.maia3Load = maia3Load;
globalThis.maia3Predict = maia3Predict;
globalThis.maia3PredictMove = maia3PredictMove;
globalThis.maia3Close = maia3Close;
