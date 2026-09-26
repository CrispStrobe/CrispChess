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
  console.log('[Frozenight WASM] set_position(' + fen + ', "' + (moves || '') + '")');

  // Debug: test if the move parses
  if (moves) {
    const debugResult = frozenightModule.debug_parse_move(fen, moves.trim());
    console.log('[Frozenight WASM] debug_parse_move: ' + debugResult);
  }

  frozenightModule.set_position(fen, moves || '');
  const currentFen = frozenightModule.get_fen();
  console.log('[Frozenight WASM] Board after: ' + currentFen);
}

function frozenightSearch(depth) {
  if (!frozenightModule) throw new Error('Not loaded');
  const move = frozenightModule.search(depth);
  console.log('[Frozenight WASM] search(' + depth + ') = ' + move);
  return move;
}

// One search bounded by a node count as well as a depth, answering
// "<uci> <nodes>". A search call cannot be interrupted once it starts, so a
// depth that turns out not to fit the time budget runs to completion however
// long that takes; the node bound is what the engine can actually honour,
// since it checks it on every node and needs no clock to do so.
//
// Returns an empty string when the loaded bundle predates `search_bounded`,
// which is the caller's signal to fall back rather than fail: the .wasm is a
// committed artifact rebuilt by CI, so it can lag the code that calls it.
function frozenightSearchBounded(depth, maxNodes) {
  if (!frozenightModule) throw new Error('Not loaded');
  if (typeof frozenightModule.search_bounded !== 'function') return '';
  return frozenightModule.search_bounded(depth, maxNodes);
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
globalThis.frozenightSearchBounded = frozenightSearchBounded;
globalThis.frozenightGetEval = frozenightGetEval;
globalThis.frozenightDispose = frozenightDispose;
globalThis.frozenightIsLoaded = frozenightIsLoaded;
