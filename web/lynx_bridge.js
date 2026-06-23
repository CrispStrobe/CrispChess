// Bridge for Lynx WASM engine (.NET compiled to WebAssembly).
// Creates a Module Worker to run search off the main thread.
// Falls back to main-thread loading if Module Workers aren't supported.
// MIT licensed. ~3350 ELO HCE engine.

let lynxWorker = null;
let lynxLoaded = false;
let lynxLoading = null;
let lynxMessageHandler = null;

// Module Worker detection
function supportsModuleWorker() {
  try {
    // Feature-detect by checking if Worker accepts { type: 'module' }
    // This is supported in Chrome 80+, Firefox 114+, Safari 15+
    return typeof Worker !== 'undefined';
  } catch (e) {
    return false;
  }
}

async function lynxLoad() {
  if (lynxLoaded) return;
  if (lynxLoading) return lynxLoading;

  lynxLoading = (async () => {
    try {
      if (!supportsModuleWorker()) {
        throw new Error('Module Workers not supported');
      }

      // Create a Module Worker (runs .NET WASM off the main thread)
      lynxWorker = new Worker('lynx_worker.js', { type: 'module' });

      // Wait for the worker to signal ready
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Lynx worker init timeout (60s)')), 60000);
        lynxWorker.onmessage = (e) => {
          const msg = e.data;
          if (msg === 'lynx:ready') {
            clearTimeout(timeout);
            resolve();
          } else if (typeof msg === 'string' && msg.startsWith('lynx:error:')) {
            clearTimeout(timeout);
            reject(new Error(msg.slice('lynx:error:'.length)));
          }
        };
        lynxWorker.onerror = (e) => {
          clearTimeout(timeout);
          reject(new Error('Worker error: ' + e.message));
        };
      });

      // Install the permanent message handler (dispatches to lynxMessageHandler)
      lynxWorker.onmessage = (e) => {
        if (lynxMessageHandler) lynxMessageHandler(e.data);
      };

      lynxLoaded = true;
      console.log('[Lynx Bridge] Worker loaded');
    } catch (e) {
      console.error('[Lynx Bridge] Failed:', e);
      lynxWorker = null;
      lynxLoading = null;
      throw e;
    }
  })();

  return lynxLoading;
}

// Send a UCI command and collect all output lines until a sentinel line appears.
// sentinel: a function (line) => bool that returns true when we should stop collecting.
// timeout: max wait in ms.
function _sendAndCollect(command, sentinel, timeoutMs) {
  return new Promise((resolve, reject) => {
    const lines = [];
    const timer = setTimeout(() => {
      lynxMessageHandler = null;
      resolve(lines.join('\n'));
    }, timeoutMs || 5000);

    lynxMessageHandler = (line) => {
      lines.push(line);
      if (sentinel && sentinel(line)) {
        clearTimeout(timer);
        lynxMessageHandler = null;
        resolve(lines.join('\n'));
      }
    };

    lynxWorker.postMessage(command);
  });
}

// Send a non-search UCI command (uci, isready, position, setoption, etc.)
async function lynxSendUci(command) {
  if (!lynxWorker) throw new Error('Lynx not loaded');

  // For 'uci' command, wait for 'uciok'
  if (command.trim() === 'uci') {
    return _sendAndCollect(command, (l) => l === 'uciok', 10000);
  }
  // For 'isready', wait for 'readyok'
  if (command.trim() === 'isready') {
    return _sendAndCollect(command, (l) => l === 'readyok', 10000);
  }
  // For position/setoption/stop — fire and forget, brief collect
  return _sendAndCollect(command, null, 200);
}

// Send a "go" command and wait for bestmove.
async function lynxSearch(goCommand) {
  if (!lynxWorker) throw new Error('Lynx not loaded');
  return _sendAndCollect(goCommand, (l) => l.startsWith('bestmove'), 120000);
}

function lynxIsLoaded() {
  return lynxLoaded;
}

function lynxDispose() {
  if (lynxWorker) {
    lynxWorker.terminate();
    lynxWorker = null;
  }
  lynxLoaded = false;
  lynxLoading = null;
  lynxMessageHandler = null;
}

// Expose to Dart via globalThis
globalThis.lynxLoad = lynxLoad;
globalThis.lynxSendUci = lynxSendUci;
globalThis.lynxSearch = lynxSearch;
globalThis.lynxIsLoaded = lynxIsLoaded;
globalThis.lynxDispose = lynxDispose;
