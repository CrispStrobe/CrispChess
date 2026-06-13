// Bridge between Dart and maia3-js on web.
// Loaded by the Flutter web app to provide Maia3 inference.
// maia3-js and onnxruntime-web are loaded from CDN on first use.

let maia3Instance = null;
let maia3Loading = false;

async function maia3Load(variant, onProgress) {
  if (maia3Instance && maia3Instance.isLoaded()) return;
  if (maia3Loading) return;
  maia3Loading = true;

  try {
    // Dynamic import from CDN (ESM)
    const { Maia3 } = await import(
      'https://cdn.jsdelivr.net/npm/maia3-js@latest/dist/web/index.js'
    );

    maia3Instance = new Maia3({
      variant: variant || '5m',
      onProgress: (loaded, total) => {
        if (onProgress) onProgress(loaded, total);
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
  if (!maia3Instance || !maia3Instance.isLoaded()) {
    throw new Error('Maia3 not loaded');
  }

  const input = {
    fen: fen,
    selfElo: selfElo || 1500,
  };

  if (oppoElo) input.oppoElo = oppoElo;
  if (priorFens && priorFens.length > 0) input.priorFens = priorFens;

  const result = await maia3Instance.predict(input);

  return {
    bestMove: result.bestMove,
    winProbability: result.winProbability,
    wdl: result.wdl,
    candidates: result.candidates.map(c => ({
      uci: c.uci,
      probability: c.probability,
      winProbability: c.winProbability,
    })),
  };
}

async function maia3Close() {
  if (maia3Instance) {
    await maia3Instance.close();
    maia3Instance = null;
  }
}

// Expose to Dart via globalThis
globalThis.maia3Load = maia3Load;
globalThis.maia3Predict = maia3Predict;
globalThis.maia3Close = maia3Close;
