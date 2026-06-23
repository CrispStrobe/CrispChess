// Bridge for Lynx WASM engine (.NET compiled to WebAssembly).
// Loads the .NET Mono runtime + Lynx assemblies on the main thread.
// UCI interface exposed to Dart via globalThis functions.
// MIT licensed. ~3350 ELO HCE engine.

let lynxInterop = null;
let lynxLoaded = false;
let lynxLoading = null;

async function lynxLoad() {
  if (lynxLoaded) return;
  if (lynxLoading) return lynxLoading;

  lynxLoading = (async () => {
    try {
      console.log('[Lynx WASM] Loading .NET runtime...');
      const { dotnet } = await import('./lynx/_framework/dotnet.js');

      const { getAssemblyExports, getConfig } = await dotnet
        .withDiagnosticTracing(false)
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

async function lynxSendUci(command) {
  if (!lynxInterop) throw new Error('Lynx not loaded');
  const result = await lynxInterop.SendCommand(command);
  return result || '';
}

async function lynxSearch(goCommand) {
  if (!lynxInterop) throw new Error('Lynx not loaded');
  const result = await lynxInterop.SendSearchCommand(goCommand);
  return result || '';
}

function lynxIsLoaded() {
  return lynxLoaded;
}

function lynxDispose() {
  lynxInterop = null;
  lynxLoaded = false;
  lynxLoading = null;
}

globalThis.lynxLoad = lynxLoad;
globalThis.lynxSendUci = lynxSendUci;
globalThis.lynxSearch = lynxSearch;
globalThis.lynxIsLoaded = lynxIsLoaded;
globalThis.lynxDispose = lynxDispose;
