#!/bin/bash
# Test all engine backends outside the Flutter app.
#
# Tests:
# 1. Lc0/Maia ONNX model download + inference (Python)
# 2. Stockfish.js UCI handshake + search (Node.js)
# 3. URL reachability for all model downloads (curl)
#
# Usage: bash scripts/test_all_engines.sh
# Requires: python3, pip (onnxruntime, numpy), node, curl

set -e
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "========================================="
echo " CrispChess Engine Tests (outside app)"
echo "========================================="
echo ""

# --- 1. URL reachability ---
echo "--- Model URL Reachability ---"

check_url() {
    local name="$1"
    local url="$2"
    local status=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 10 "$url")
    if [ "$status" -ge 200 ] && [ "$status" -lt 400 ]; then
        pass "$name ($status)"
    else
        fail "$name (HTTP $status)"
    fi
}

# Lc0/Maia models
for elo in 1100 1300 1500 1700 1900; do
    check_url "Maia $elo ONNX" \
        "https://huggingface.co/cstr/maia-chess-onnx-opset15/resolve/main/maia-${elo}-opset15.onnx"
done

# Maia3 models
for variant in 5m 23m 79m; do
    check_url "Maia3 $variant" \
        "https://huggingface.co/cemoss17/maia3-onnx/resolve/main/maia3_${variant}.onnx"
done

# Stockfish
check_url "Stockfish 10 JS" \
    "https://cdn.jsdelivr.net/npm/stockfish.js@10.0.2/stockfish.js"

# ONNX Runtime WASM
check_url "ORT WASM binary" \
    "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.21.0/dist/ort-wasm-simd-threaded.wasm"

echo ""

# --- 2. Lc0 ONNX inference ---
echo "--- Lc0/Maia ONNX Inference ---"
if command -v python3 &>/dev/null && python3 -c "import onnxruntime" 2>/dev/null; then
    if python3 scripts/test_lc0_onnx.py 1500 2>&1 | tail -1 | grep -q "PASS"; then
        pass "Maia 1500 ONNX inference"
    else
        fail "Maia 1500 ONNX inference"
    fi
else
    echo "  ⊘ Skipped (needs: pip install onnxruntime numpy)"
fi

echo ""

# --- 3. Stockfish.js ---
echo "--- Stockfish.js UCI Test ---"
if command -v node &>/dev/null; then
    if bash scripts/test_stockfish_js.sh 2>&1 | tail -1 | grep -q "PASS"; then
        pass "Stockfish.js UCI"
    else
        fail "Stockfish.js UCI"
    fi
else
    echo "  ⊘ Skipped (needs: node)"
fi

echo ""
echo "========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "========================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
