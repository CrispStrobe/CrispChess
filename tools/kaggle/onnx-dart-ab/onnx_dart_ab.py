"""CrispChess pure-Dart experiment matrix plus a genuine ORT CUDA arm."""

import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time
import urllib.request

WORK = Path("/kaggle/working")
RESULT = WORK / "onnx_dart_ab.json"
SCRIPT_VERSION = "v1"
RUNTIME_SHA = "d9afbe2b694ab1fa26c959ab918b7bc8a9ed06a2"
MODEL_URL = "https://huggingface.co/cstr/maia-chess-onnx-opset15/resolve/main/maia-1500.onnx"


def run(command, **kwargs):
    print("+", " ".join(map(str, command)), flush=True)
    return subprocess.run(command, check=True, text=True, **kwargs)


def gpu_info():
    try:
        return subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,compute_cap,driver_version", "--format=csv,noheader"],
            text=True,
        ).strip()
    except Exception as error:
        return f"unavailable: {error}"


print(f"SCRIPT_VERSION={SCRIPT_VERSION} RUNTIME_SHA={RUNTIME_SHA}", flush=True)
print(f"GPU={gpu_info()}", flush=True)

dart_zip = WORK / "dartsdk.zip"
dart_dir = WORK / "dart-sdk"
if not dart_dir.exists():
    urllib.request.urlretrieve(
        "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip",
        dart_zip,
    )
    run(["unzip", "-q", str(dart_zip), "-d", str(WORK)])
dart = str(dart_dir / "bin" / "dart")

repo = WORK / "onnx_runtime_dart"
if not repo.exists():
    run(["git", "clone", "--filter=blob:none", "https://github.com/CrispStrobe/onnx_runtime_dart.git", str(repo)])
run(["git", "-C", str(repo), "checkout", "--detach", RUNTIME_SHA])
run([dart, "pub", "get"], cwd=repo)

model = WORK / "maia-1500.onnx"
if not model.exists():
    urllib.request.urlretrieve(MODEL_URL, model)

variants = {
    "default": "",
    "inPlaceRelu": "inPlaceRelu",
    "inPlaceAddRelu": "inPlaceAddRelu",
    "cacheAttributes": "cacheAttributes",
    "narrowDirectGemm": "narrowDirectGemm",
    "all": "inPlaceRelu,inPlaceAddRelu,cacheAttributes,narrowDirectGemm",
}
samples = {name: [] for name in variants}
wall_re = re.compile(r"wall: min=([0-9.]+)ms mean=([0-9.]+)ms")

# Rotate order on every round to reduce thermal/load ordering bias.
names = list(variants)
for round_index in range(5):
    order = names[round_index:] + names[:round_index]
    for name in order:
        command = [dart, "run", "tool/bench.dart", str(model), "--iters", "30"]
        if variants[name]:
            command += ["--experiments", variants[name]]
        completed = run(command, cwd=repo, capture_output=True)
        print(completed.stdout, flush=True)
        match = wall_re.search(completed.stdout)
        if not match:
            raise RuntimeError(f"No benchmark result for {name}")
        samples[name].append({"min_ms": float(match.group(1)), "mean_ms": float(match.group(2))})

dart_summary = {
    name: {
        "median_min_ms": statistics.median(x["min_ms"] for x in values),
        "median_mean_ms": statistics.median(x["mean_ms"] for x in values),
        "samples": values,
    }
    for name, values in samples.items()
}

# This is the actual GPU test. It is intentionally separate from pure Dart.
ort_result = {"available": False}
try:
    run([sys.executable, "-m", "pip", "install", "-q", "onnxruntime-gpu", "numpy"])
    import numpy as np
    import onnxruntime as ort

    providers = ort.get_available_providers()
    selected = ["CUDAExecutionProvider", "CPUExecutionProvider"]
    session = ort.InferenceSession(str(model), providers=selected)
    actual_providers = session.get_providers()
    input_meta = session.get_inputs()[0]
    feed = {input_meta.name: np.zeros((1, 112, 8, 8), dtype=np.float32)}
    for _ in range(20):
        session.run(None, feed)
    timings = []
    for _ in range(100):
        start = time.perf_counter()
        session.run(None, feed)
        timings.append((time.perf_counter() - start) * 1000)
    ort_result = {
        "available": "CUDAExecutionProvider" in actual_providers,
        "available_providers": providers,
        "session_providers": actual_providers,
        "median_ms": statistics.median(timings),
        "min_ms": min(timings),
    }
except Exception as error:
    ort_result = {"available": False, "error": repr(error)}

result = {
    "script_version": SCRIPT_VERSION,
    "runtime_sha": RUNTIME_SHA,
    "gpu": gpu_info(),
    "pure_dart_cpu": dart_summary,
    "onnxruntime_gpu": ort_result,
}
RESULT.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2), flush=True)
