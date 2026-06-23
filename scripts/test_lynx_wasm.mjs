// Test Lynx WASM engine in Node.js
// Validates UCI protocol: uci → uciok, position + go → bestmove

import { dotnet } from '../web/lynx/_framework/dotnet.js';

async function main() {
  console.log('[Test] Loading .NET WASM runtime...');

  const { getAssemblyExports, getConfig } = await dotnet
    .withDiagnosticTracing(false)
    .create();

  const config = getConfig();
  const exports = await getAssemblyExports(config.mainAssemblyName);
  const interop = exports.LynxWasm.UciInterop;

  // Test 1: Initialize
  console.log('[Test] Initializing engine...');
  const initResult = await interop.Initialize();
  console.log(`[Test] Init: ${initResult}`);
  if (initResult !== 'ok') {
    console.error('FAIL: Init returned', initResult);
    process.exit(1);
  }
  console.log('PASS: Initialize');

  // Test 2: UCI handshake
  console.log('[Test] Sending "uci"...');
  const uciResult = await interop.SendCommand('uci');
  console.log(`[Test] UCI response (${uciResult.length} chars):`);
  for (const line of uciResult.split('\n').slice(0, 5)) {
    console.log(`  ${line}`);
  }
  if (!uciResult.includes('uciok')) {
    console.error('FAIL: No uciok in response');
    process.exit(1);
  }
  console.log('PASS: UCI handshake (uciok received)');

  // Test 3: isready
  const readyResult = await interop.SendCommand('isready');
  if (!readyResult.includes('readyok')) {
    console.error('FAIL: No readyok');
    process.exit(1);
  }
  console.log('PASS: isready → readyok');

  // Test 4: Position + search
  console.log('[Test] Setting position and searching depth 6...');
  await interop.SendCommand('position startpos');
  const searchResult = await interop.SendSearchCommand('go depth 6');
  console.log(`[Test] Search result (${searchResult.length} chars):`);
  for (const line of searchResult.split('\n')) {
    if (line.trim()) console.log(`  ${line.trim()}`);
  }

  if (!searchResult.includes('bestmove')) {
    console.error('FAIL: No bestmove in search output');
    process.exit(1);
  }

  const bestmoveLine = searchResult.split('\n').find(l => l.includes('bestmove'));
  const bestmove = bestmoveLine.trim().split(' ')[1];
  console.log(`PASS: Search completed, bestmove = ${bestmove}`);

  // Test 5: Search from a specific position
  console.log('[Test] Testing from Sicilian Defense...');
  await interop.SendCommand('position startpos moves e2e4 c7c5');
  const result2 = await interop.SendSearchCommand('go depth 6');
  const bm2 = result2.split('\n').find(l => l.includes('bestmove'));
  if (!bm2) {
    console.error('FAIL: No bestmove from Sicilian position');
    process.exit(1);
  }
  console.log(`PASS: Sicilian bestmove = ${bm2.trim().split(' ')[1]}`);

  console.log('\n=== ALL TESTS PASSED ===');
  process.exit(0);
}

main().catch(e => {
  console.error('FATAL:', e);
  process.exit(1);
});
