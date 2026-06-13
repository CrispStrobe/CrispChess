// Bridge for Frozenight WASM engine.
// Loads frozenight_wasm.js + .wasm, exposes UCI-like interface to Dart.
// MIT/Apache-2.0 licensed. ~2960 ELO NNUE engine.

let frozenightModule = null;
let frozenightLoaded = false;

async function frozenightLoad() {
  if (frozenightLoaded) return;
  try {
    // Load the wasm-bindgen generated JS + WASM
    const module = await import('./frozenight_wasm.js');
    await module.default(); // Initialize WASM
    module.init(16); // 16MB hash table
    frozenightModule = module;
    frozenightLoaded = true;
    console.log('[Frozenight WASM] Loaded');
  } catch (e) {
    console.error('[Frozenight WASM] Failed to load:', e);
    throw e;
  }
}

function frozenightSetPosition(fen, moves) {
  if (!frozenightModule) throw new Error('Not loaded');
  console.log('[Frozenight WASM] set_position(' + fen + ', ' + (moves || '') + ')');
  frozenightModule.set_position(fen, moves || '');
}

function frozenightSearch(depth) {
  if (!frozenightModule) throw new Error('Not loaded');
  const move = frozenightModule.search(depth);
  console.log('[Frozenight WASM] search(' + depth + ') = ' + move);
  return move;
}

function frozenightGetEval() {
  if (!frozenightModule) return 0;
  return frozenightModule.get_eval();
}

function frozenightDispose() {
  if (frozenightModule) {
    frozenightModule.dispose();
    frozenightModule = null;
    frozenightLoaded = false;
  }
}

function frozenightIsLoaded() {
  return frozenightLoaded;
}

// Expose to Dart
globalThis.frozenightLoad = frozenightLoad;
globalThis.frozenightSetPosition = frozenightSetPosition;
globalThis.frozenightSearch = frozenightSearch;
globalThis.frozenightGetEval = frozenightGetEval;
globalThis.frozenightDispose = frozenightDispose;
globalThis.frozenightIsLoaded = frozenightIsLoaded;
