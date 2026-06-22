// Bridge for Lynx WASM engine (.NET compiled to WebAssembly).
// Loads the .NET Mono runtime + Lynx assemblies, exposes UCI interface to Dart.
// MIT licensed. ~3350 ELO HCE engine.

let lynxInterop = null;
let lynxLoaded = false;
let lynxLoading = null;

async function lynxLoad() {
  if (lynxLoaded) return;
  if (lynxLoading) return lynxLoading;

  lynxLoading = (async () => {
    try {
      // Import the .NET WASM runtime (ES module)
      const { dotnet } = await import('./lynx/_framework/dotnet.js');

      const { getAssemblyExports, getConfig } = await dotnet
        .withDiagnosticTracing(false)
        .withConfig({ locateFile: (path) => './lynx/_framework/' + path })
        .create();

      const config = getConfig();
      const exports = await getAssemblyExports(config.mainAssemblyName);

      lynxInterop = exports.LynxWasm.UciInterop;

      const result = await lynxInterop.Initialize();
      if (result !== 'ok' && result !== 'already initialized') {
        throw new Error('Lynx init failed: ' + result);
      }

      lynxLoaded = true;
      console.log('[Lynx WASM] Loaded and initialized');
    } catch (e) {
      console.error('[Lynx WASM] Failed to load:', e);
      lynxLoading = null;
      throw e;
    }
  })();

  return lynxLoading;
}

// Send a UCI command (non-search: uci, isready, position, setoption, etc.)
// Returns the engine's output lines as a single string.
async function lynxSendUci(command) {
  if (!lynxInterop) throw new Error('Lynx not loaded');
  const result = await lynxInterop.SendCommand(command);
  return result || '';
}

// Send a "go" command and wait for bestmove.
// Returns all output including info lines and bestmove.
async function lynxSearch(goCommand) {
  if (!lynxInterop) throw new Error('Lynx not loaded');
  const result = await lynxInterop.SendSearchCommand(goCommand);
  return result || '';
}

// Poll any pending engine output (for streaming info lines during search).
function lynxPollOutput() {
  if (!lynxInterop) return '';
  return lynxInterop.PollOutput();
}

function lynxIsLoaded() {
  return lynxLoaded;
}

function lynxDispose() {
  lynxInterop = null;
  lynxLoaded = false;
  lynxLoading = null;
}

// Expose to Dart via globalThis
globalThis.lynxLoad = lynxLoad;
globalThis.lynxSendUci = lynxSendUci;
globalThis.lynxSearch = lynxSearch;
globalThis.lynxPollOutput = lynxPollOutput;
globalThis.lynxIsLoaded = lynxIsLoaded;
globalThis.lynxDispose = lynxDispose;
