"""Export the permissively licensed chess language models with a KV cache.

One graph per model: (input_ids [b, t], past k/v per layer [b, h, p, d]) ->
(logits of the last position [b, vocab], present k/v [b, h, p + t, d]).
The app feeds the game once and then only each new move's tokens, and scores
candidate moves by extending a copy of the cache by a token or two — instead
of re-reading the whole game for every candidate. The first call passes an
empty cache (p = 0).

Verified against the PyTorch model's full forward pass: incremental prefill
+ steps, a batch of branches from one shared prefix, several lengths.
Large graphs are also written with fp16 weight storage (fp32 compute).
Runs on a Kaggle CPU worker (it has internet); outputs in /kaggle/working.
"""
import json, os, shutil, subprocess, sys, time, traceback
from pathlib import Path

subprocess.run([sys.executable, "-m", "pip", "install", "-q", "onnx", "onnxruntime"], check=False)

import numpy as np, torch, onnx, onnxruntime as ort
from huggingface_hub import snapshot_download
from transformers import AutoModelForCausalLM, AutoTokenizer, DynamicCache

torch.set_grad_enabled(False)
OUT = Path("/kaggle/working")
MODELS = [
    ("FlameF0X/ChessSLM", "apache-2.0"),
    ("FlameF0X/ChessSLM-PM", "apache-2.0"),
    ("TobiasLogic/ChessAggro", "apache-2.0"),
    ("mlabonne/chesspythia-70m", "apache-2.0"),
    ("mlabonne/grandpythia-200k-70m", "apache-2.0"),
    ("bharathrajcl/chess_llama_68m", "apache-2.0"),
    ("nlpguy/smolchess-v2", "apache-2.0"),
    ("nlpguy/amdchess-v9", "apache-2.0"),
    ("DedeProGames/dialochess", "mit"),
    ("DedeProGames/Chesser-248K-Mini", "apache-2.0"),
    ("nsarrazin/chessformer", "mit"),
]
FP16_ABOVE_BYTES = 250_000_000
report = {}


def progress(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)
    with open(OUT / "progress.txt", "a") as f:
        f.write(msg + "\n")


def cache_tensors(pk, n):
    if hasattr(pk, "layers"):
        return [t for i in range(n) for t in (pk.layers[i].keys, pk.layers[i].values)]
    return [t for i in range(n) for t in (pk.key_cache[i], pk.value_cache[i])]


class WithPast(torch.nn.Module):
    def __init__(self, m, n):
        super().__init__(); self.m = m; self.n = n

    def forward(self, input_ids, *past):
        b, t = input_ids.shape
        p = past[0].shape[2]
        cache = DynamicCache()
        for i in range(self.n):
            cache.update(past[2 * i], past[2 * i + 1], i)
        mask = torch.ones(b, p + t, dtype=torch.long)
        out = self.m(input_ids=input_ids, attention_mask=mask, past_key_values=cache, use_cache=True)
        return (out.logits[:, -1, :], *cache_tensors(out.past_key_values, self.n))


def fp16_storage(src, dst):
    from onnx import helper, numpy_helper, TensorProto
    m = onnx.load(str(src))
    g = m.graph
    inits, casts = [], []
    for init in list(g.initializer):
        if init.data_type == TensorProto.FLOAT and np.prod(init.dims) >= 1024:
            h = numpy_helper.from_array(numpy_helper.to_array(init).astype(np.float16), init.name + "_fp16")
            inits.append(h)
            casts.append(helper.make_node("Cast", [h.name], [init.name], to=TensorProto.FLOAT, name=init.name + "_cast"))
        else:
            inits.append(init)
    del g.initializer[:]; g.initializer.extend(inits)
    nodes = casts + list(g.node); del g.node[:]; g.node.extend(nodes)
    onnx.save(m, str(dst))


def info(path):
    m = onnx.load(str(path), load_external_data=False)
    return {"ir_version": m.ir_version, "opsets": {o.domain or "ai.onnx": o.version for o in m.opset_import},
            "ops": sorted({n.op_type for n in m.graph.node}), "bytes": Path(path).stat().st_size,
            "inputs": [(i.name, [d.dim_param or d.dim_value for d in i.type.tensor_type.shape.dim]) for i in m.graph.input][:3]}


def verify(path, model, n, vocab, heads, hdim):
    """Incremental ONNX vs PyTorch full forward."""
    so = ort.SessionOptions(); so.intra_op_num_threads = 1
    s = ort.InferenceSession(str(path), so, providers=["CPUExecutionProvider"])
    names = [i.name for i in s.get_inputs()]
    worst = 0.0
    for plen in (5, 40, 150):
        ids = torch.randint(0, vocab, (1, plen + 3))
        full = model(input_ids=ids, attention_mask=torch.ones_like(ids), use_cache=False).logits[0].numpy()
        empty = [np.zeros((1, heads, 0, hdim), np.float32)] * (2 * n)
        o = s.run(None, dict(zip(names, [ids[:, :plen].numpy()] + empty)))
        worst = max(worst, float(np.abs(o[0][0] - full[plen - 1]).max()))
        past = o[1:]
        for k in range(3):   # one token at a time
            o = s.run(None, dict(zip(names, [ids[:, plen + k:plen + k + 1].numpy()] + list(past))))
            worst = max(worst, float(np.abs(o[0][0] - full[plen + k]).max()))
            past = o[1:]
    # a batch of branches from a shared prefix
    pre = torch.randint(0, vocab, (1, 30)); nxt = torch.randint(0, vocab, (4, 2))
    o = s.run(None, dict(zip(names, [pre.numpy()] + [np.zeros((1, heads, 0, hdim), np.float32)] * (2 * n))))
    past = [np.repeat(t, 4, axis=0) for t in o[1:]]
    ob = s.run(None, dict(zip(names, [nxt.numpy()] + past)))
    for i in range(4):
        ids = torch.cat([pre[0], nxt[i]]).unsqueeze(0)
        ref = model(input_ids=ids, attention_mask=torch.ones_like(ids), use_cache=False).logits[0, -1].numpy()
        worst = max(worst, float(np.abs(ob[0][i] - ref).max()))
    # latency: 250-token prefill, then a 1-token step and a batch-20 step
    ids = torch.randint(0, vocab, (1, 250)).numpy()
    t0 = time.perf_counter(); o = s.run(None, dict(zip(names, [ids] + [np.zeros((1, heads, 0, hdim), np.float32)] * (2 * n))))
    pre_ms = (time.perf_counter() - t0) * 1000
    t0 = time.perf_counter(); s.run(None, dict(zip(names, [ids[:, :1]] + list(o[1:])))); step_ms = (time.perf_counter() - t0) * 1000
    past20 = [np.repeat(t, 20, axis=0) for t in o[1:]]
    t0 = time.perf_counter(); s.run(None, dict(zip(names, [np.repeat(ids[:, :1], 20, 0)] + past20))); b20_ms = (time.perf_counter() - t0) * 1000
    return worst, {"prefill250_ms": round(pre_ms, 1), "step_ms": round(step_ms, 1), "batch20_step_ms": round(b20_ms, 1)}


for repo, licence in MODELS:
    name = repo.split("/")[1]; d = OUT / name; d.mkdir(exist_ok=True)
    r = report[name] = {"repo": repo, "licence": licence}
    try:
        progress(f"{repo}: download")
        local = Path(snapshot_download(repo))
        for f in ("tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt",
                  "special_tokens_map.json", "config.json", "README.md", "LICENSE", "generation_config.json"):
            if (local / f).exists(): shutil.copy(local / f, d / f)
        model = AutoModelForCausalLM.from_pretrained(local, torch_dtype=torch.float32, attn_implementation="eager").eval()
        cfg = model.config
        n = cfg.num_hidden_layers
        vocab = cfg.vocab_size
        # Probe the cache layout rather than trusting config field names.
        probe = model(input_ids=torch.zeros(1, 3, dtype=torch.long), attention_mask=torch.ones(1, 3, dtype=torch.long), use_cache=True)
        k0 = cache_tensors(probe.past_key_values, n)[0]
        heads, hdim = k0.shape[1], k0.shape[3]
        r.update({"layers": n, "kv_heads": heads, "head_dim": hdim, "vocab": vocab,
                  "params_M": round(sum(p.numel() for p in model.parameters()) / 1e6, 1)})
        progress(f"{repo}: export (layers {n}, kv heads {heads}, head dim {hdim})")
        wrapper = WithPast(model, n).eval()
        dummy_past = [torch.zeros(1, heads, 4, hdim) for _ in range(2 * n)]
        names_in = ["input_ids"] + [f"past_{kv}_{i}" for i in range(n) for kv in ("key", "value")]
        names_out = ["logits"] + [f"present_{kv}_{i}" for i in range(n) for kv in ("key", "value")]
        dyn = {"input_ids": {0: "b", 1: "t"}, "logits": {0: "b"}}
        for nm in names_in[1:]: dyn[nm] = {0: "b", 2: "p"}
        for nm in names_out[1:]: dyn[nm] = {0: "b", 2: "pt"}
        torch.onnx.export(wrapper, (torch.zeros(1, 3, dtype=torch.long), *dummy_past), str(d / "model_kv.onnx"),
                          input_names=names_in, output_names=names_out, dynamic_axes=dyn,
                          opset_version=17, do_constant_folding=True, dynamo=False)
        model.eval()
        r["onnx"] = info(d / "model_kv.onnx")
        r["max_abs_diff"], r["latency"] = verify(d / "model_kv.onnx", model, n, vocab, heads, hdim)
        progress(f"{repo}: diff {r['max_abs_diff']:.2e} {r['latency']}")
        if r["onnx"]["bytes"] > FP16_ABOVE_BYTES:
            fp16_storage(d / "model_kv.onnx", d / "model_kv_fp16.onnx")
            w16, _ = verify(d / "model_kv_fp16.onnx", model, n, vocab, heads, hdim)
            r["fp16"] = {"bytes": (d / "model_kv_fp16.onnx").stat().st_size, "max_abs_diff": w16}
            (d / "model_kv.onnx").unlink()   # keep the output under Kaggle's download limits
            progress(f"{repo}: fp16 {r['fp16']}")
        r["status"] = "ok"
        del model
    except Exception as e:
        r["status"] = "error: " + repr(e)[:500]; r["trace"] = traceback.format_exc()[-3000:]
        progress(f"{repo}: FAILED {e!r}")
    finally:
        (OUT / "report.json").write_text(json.dumps(report, indent=1, default=str))
progress("done")
