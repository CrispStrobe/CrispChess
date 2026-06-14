#!/bin/bash
# Test Stockfish.js works outside the app via Node.js
#
# Usage: bash scripts/test_stockfish_js.sh
# Requires: node

set -e

echo "=== Stockfish.js CLI Test ==="

# Download if needed
SF_PATH="/tmp/stockfish-test.js"
if [ ! -f "$SF_PATH" ]; then
    echo "Downloading Stockfish 10 from CDN..."
    curl -sL "https://cdn.jsdelivr.net/npm/stockfish.js@10.0.2/stockfish.js" -o "$SF_PATH"
    echo "  Downloaded $(wc -c < "$SF_PATH") bytes"
fi

# Run UCI handshake + search via Node.js
node -e "
const { Worker } = require('worker_threads');
const w = new Worker('$SF_PATH');

let gotUciOk = false;
let gotBestMove = false;

w.on('message', (line) => {
    if (typeof line !== 'string') return;
    if (line.includes('uciok')) {
        console.log('  UCI handshake: OK');
        gotUciOk = true;
        w.postMessage('isready');
    }
    if (line.includes('readyok')) {
        console.log('  Engine ready: OK');
        w.postMessage('position startpos');
        w.postMessage('go depth 5');
    }
    if (line.startsWith('bestmove')) {
        const move = line.split(' ')[1];
        console.log('  Best move (depth 5): ' + move);
        gotBestMove = true;

        // Validate move format
        if (move.length >= 4 && move.match(/^[a-h][1-8][a-h][1-8]/)) {
            console.log('  Move format: VALID');
        } else {
            console.error('  Move format: INVALID');
            process.exit(1);
        }

        w.postMessage('quit');
        setTimeout(() => {
            console.log('');
            console.log('=== PASS: Stockfish.js works correctly ===');
            process.exit(0);
        }, 500);
    }
});

w.on('error', (err) => {
    console.error('Worker error:', err);
    process.exit(1);
});

w.postMessage('uci');

// Timeout
setTimeout(() => {
    if (!gotBestMove) {
        console.error('TIMEOUT: No response from Stockfish');
        process.exit(1);
    }
}, 15000);
"
