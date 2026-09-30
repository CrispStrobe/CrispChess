// Lynx chess engine Web Worker (ES module).
// Runs the .NET WASM runtime + Lynx engine off the main thread.
// Communicates with the main thread via postMessage (UCI protocol).

let lynxInterop = null;
let initialized = false;

async function initLynx() {
  if (initialized) return;

  try {
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

    initialized = true;
    postMessage('lynx:ready');
  } catch (e) {
    postMessage('lynx:error:' + e.message);
    console.error('[Lynx Worker] Init failed:', e);
  }
}

self.onmessage = async function (e) {
  const command = e.data;

  if (command === 'lynx:init') {
    await initLynx();
    return;
  }

  if (!initialized || !lynxInterop) {
    postMessage('error: not initialized');
    return;
  }

  try {
    const trimmed = command.trim();

    if (trimmed.startsWith('go')) {
      // Search command — use SendSearchCommand which waits for bestmove
      const result = await lynxInterop.SendSearchCommand(command);
      if (result) {
        for (const line of result.split('\n')) {
          if (line.trim()) postMessage(line.trim());
        }
      }
    } else {
      // Non-search UCI commands (position, uci, isready, setoption, stop, etc.)
      const result = await lynxInterop.SendCommand(command);
      if (result) {
        for (const line of result.split('\n')) {
          if (line.trim()) postMessage(line.trim());
        }
      }
    }
  } catch (e) {
    console.error('[Lynx Worker] Error:', command, e);
    postMessage('error: ' + e.message);
  }
};

// Auto-init on worker load
initLynx();
