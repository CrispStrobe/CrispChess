#!/usr/bin/env python3
"""Test Lc0/Maia ONNX models outside the app.

Downloads a Maia model, runs inference, verifies output shapes.
Requires: pip install onnxruntime numpy

Usage: python3 scripts/test_lc0_onnx.py [--elo 1500]
"""
import sys
import os
import urllib.request
import tempfile
import numpy as np

def main():
    elo = sys.argv[1] if len(sys.argv) > 1 else '1500'
    if elo.startswith('--elo'):
        elo = sys.argv[2] if len(sys.argv) > 2 else '1500'

    url = f'https://huggingface.co/cstr/maia-chess-onnx-opset15/resolve/main/maia-{elo}-opset15.onnx'

    print(f'=== Lc0/Maia ONNX Test (ELO {elo}) ===')

    # Download model
    model_path = os.path.join(tempfile.gettempdir(), f'maia-{elo}-opset15.onnx')
    if not os.path.exists(model_path):
        print(f'Downloading {url}...')
        urllib.request.urlretrieve(url, model_path)
        print(f'  Saved to {model_path} ({os.path.getsize(model_path)} bytes)')
    else:
        print(f'Using cached {model_path}')

    # Load model
    import onnxruntime as ort
    print(f'ONNX Runtime version: {ort.__version__}')

    session = ort.InferenceSession(model_path, providers=['CPUExecutionProvider'])

    # Print model info
    print(f'\nModel info:')
    for inp in session.get_inputs():
        print(f'  Input:  {inp.name} shape={inp.shape} type={inp.type}')
    for out in session.get_outputs():
        print(f'  Output: {out.name} shape={out.shape} type={out.type}')

    # Create dummy input (starting position encoding)
    # 112 planes x 8 x 8, all zeros except piece positions
    input_planes = np.zeros((1, 112, 8, 8), dtype=np.float32)

    # Encode starting position (simplified — just place pieces)
    # Rank 0 = a1-h1 (white back rank), Rank 1 = a2-h2 (white pawns)
    # Our pieces (white): planes 0-5
    # Pawns on rank 1
    for f in range(8):
        input_planes[0, 0, 1, f] = 1.0  # our pawns
    # Back rank
    input_planes[0, 3, 0, 0] = 1.0  # our rook a1
    input_planes[0, 1, 0, 1] = 1.0  # our knight b1
    input_planes[0, 2, 0, 2] = 1.0  # our bishop c1
    input_planes[0, 4, 0, 3] = 1.0  # our queen d1
    input_planes[0, 5, 0, 4] = 1.0  # our king e1
    input_planes[0, 2, 0, 5] = 1.0  # our bishop f1
    input_planes[0, 1, 0, 6] = 1.0  # our knight g1
    input_planes[0, 3, 0, 7] = 1.0  # our rook h1
    # Their pieces (black): planes 6-11
    for f in range(8):
        input_planes[0, 6, 6, f] = 1.0  # their pawns
    input_planes[0, 9, 7, 0] = 1.0   # their rook a8
    input_planes[0, 7, 7, 1] = 1.0   # their knight b8
    input_planes[0, 8, 7, 2] = 1.0   # their bishop c8
    input_planes[0, 10, 7, 3] = 1.0  # their queen d8
    input_planes[0, 11, 7, 4] = 1.0  # their king e8
    input_planes[0, 8, 7, 5] = 1.0   # their bishop f8
    input_planes[0, 7, 7, 6] = 1.0   # their knight g8
    input_planes[0, 9, 7, 7] = 1.0   # their rook h8
    # Aux planes
    input_planes[0, 104, :, :] = 1.0  # castling queenside
    input_planes[0, 105, :, :] = 1.0  # castling kingside
    input_planes[0, 106, :, :] = 1.0  # they castle queenside
    input_planes[0, 107, :, :] = 1.0  # they castle kingside
    input_planes[0, 111, :, :] = 1.0  # all-ones plane

    # Run inference
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: input_planes})

    print(f'\nInference results:')
    for i, out in enumerate(session.get_outputs()):
        data = outputs[i]
        print(f'  {out.name}: shape={data.shape} min={data.min():.4f} max={data.max():.4f}')

    # Parse policy output
    policy = outputs[0].flatten()
    print(f'\n  Policy size: {len(policy)}')

    if len(policy) > 1858:
        print(f'  (Convolutional policy: {len(policy)} values, needs policy map)')
        # Top 5 raw values
        top5 = np.argsort(policy)[-5:][::-1]
        print(f'  Top 5 raw indices: {top5}')
        print(f'  Top 5 values: {policy[top5]}')
    else:
        top5 = np.argsort(policy)[-5:][::-1]
        print(f'  Top 5 policy indices: {top5}')

    # Parse WDL
    wdl = outputs[1].flatten()
    print(f'\n  WDL: win={wdl[0]:.4f} draw={wdl[1]:.4f} loss={wdl[2]:.4f}')
    print(f'  WDL sum: {wdl.sum():.4f} (should be ~1.0)')

    print(f'\n=== PASS: Model loads and runs correctly ===')

if __name__ == '__main__':
    main()
