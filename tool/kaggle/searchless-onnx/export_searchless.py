"""Export DeepMind's searchless-chess action-value transformers to ONNX.

google-deepmind/searchless_chess: code Apache-2.0, weights CC BY 4.0.
The checkpoints are loaded with the repository's own JAX code, rebuilt as an
equivalent PyTorch module from those parameters, checked against JAX on real
positions (log-probabilities and the move each engine picks), and exported:

  tokens int64 [b, 79]  (77 FEN tokens, the move's action id, a 0)
    -> log_probs float32 [b, 128]  (return buckets for that move)

Also writes the action vocabulary and bucket values for the app. Runs on a
Kaggle CPU worker; outputs in /kaggle/working.
"""
import json, os, subprocess, sys, time, traceback, zipfile, urllib.request
from pathlib import Path

OUT = Path("/kaggle/working"); WORK = Path("/kaggle/temp"); WORK.mkdir(exist_ok=True)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "dm-haiku", "orbax-checkpoint",
                "jaxtyping", "chess", "onnx", "onnxruntime", "apache-beam", "grain"], check=False)

def progress(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)
    with open(OUT / "progress.txt", "a") as f: f.write(msg + "\n")

repo = WORK / "searchless_chess"
if not repo.exists():
    subprocess.run(["git", "clone", "--depth", "1", "https://github.com/google-deepmind/searchless_chess.git", str(repo)], check=True)
sys.path.insert(0, str(WORK))  # package name: searchless_chess

import numpy as np, torch, onnx, onnxruntime as ort, chess
import jax, jax.numpy as jnp
import jax.sharding
from jax import random as jrandom
# The repository (2024) annotates a helper with jax.sharding.PositionalSharding,
# which current JAX has removed; it is only a type annotation.
if not hasattr(jax.sharding, "PositionalSharding"):
    jax.sharding.PositionalSharding = jax.sharding.NamedSharding
from searchless_chess.src import tokenizer, transformer, utils, training_utils
from searchless_chess.src.engines import neural_engines, engine as sc_engine

torch.set_grad_enabled(False)
CONFIGS = {"9M": (8, 256, 8), "136M": (8, 1024, 8), "270M": (16, 1024, 8)}
report = {}

# Tables the app needs, exactly as the repository computes them.
_, bucket_values = utils.get_uniform_buckets_edges_values(128)
(OUT / "actions.json").write_text(json.dumps([utils.ACTION_TO_MOVE[i] for i in range(utils.NUM_ACTIONS)]))
(OUT / "bucket_values.json").write_text(json.dumps([float(v) for v in bucket_values]))
progress(f"{utils.NUM_ACTIONS} actions, {len(bucket_values)} buckets")


def name(base, i):
    return base if i == 0 else f"{base}_{i}"


class Searchless(torch.nn.Module):
    """transformer_decoder of the repository, in PyTorch."""
    def __init__(self, p, layers, dim, heads):
        super().__init__()
        t = lambda a: torch.tensor(np.asarray(a), dtype=torch.float32)
        self.layers, self.dim, self.heads = layers, dim, heads
        self.embed = t(p["embed"]["embeddings"])
        self.pos = t(p["embed_1"]["embeddings"])
        self.ln = [(t(p[name("layer_norm", i)]["scale"]), t(p[name("layer_norm", i)]["offset"])) for i in range(2 * layers + 1)]
        self.attn = []
        for i in range(layers):
            m = name("multi_head_dot_product_attention", i)
            self.attn.append([t(p[f"{m}/{name('linear', k)}"]["w"]) for k in range(4)])
        self.mlp = [[t(p[name("linear", 3 * i + k)]["w"]) for k in range(3)] for i in range(layers)]
        head = p[name("linear", 3 * layers)]
        self.head_w, self.head_b = t(head["w"]), t(head["b"])
        # Register every weight as a parameter: plain tensors would be traced
        # into the graph as Constant nodes instead of initializers, which
        # defeats the fp16-storage pass and, for 270M, overflows protobuf.
        self._n = 0
        def reg(x):
            prm = torch.nn.Parameter(x, requires_grad=False)
            self.register_parameter(f"w{self._n}", prm); self._n += 1
            return prm
        self.embed, self.pos = reg(self.embed), reg(self.pos)
        self.ln = [(reg(a), reg(b)) for a, b in self.ln]
        self.attn = [[reg(w) for w in ws] for ws in self.attn]
        self.mlp = [[reg(w) for w in ws] for ws in self.mlp]
        self.head_w, self.head_b = reg(self.head_w), reg(self.head_b)

    @staticmethod
    def layer_norm(x, s, o):
        m = x.mean(-1, keepdim=True); v = ((x - m) ** 2).mean(-1, keepdim=True)
        return (x - m) / torch.sqrt(v + 1e-5) * s + o

    def forward(self, tokens):
        b, T = tokens.shape
        inputs = torch.cat([torch.zeros_like(tokens[:, :1]), tokens[:, :-1]], 1)  # shift_right
        h = self.embed[inputs] * (self.dim ** 0.5) + self.pos[:T]
        hd = self.dim // self.heads
        for i in range(self.layers):
            x = self.layer_norm(h, *self.ln[2 * i])
            wq, wk, wv, wo = self.attn[i]
            q = (x @ wq).view(b, T, self.heads, hd); k = (x @ wk).view(b, T, self.heads, hd); v = (x @ wv).view(b, T, self.heads, hd)
            # Same maths as the repository's einsums, written as batched
            # matmuls: the pure-Dart interpreter runs MatMul far faster than
            # its general Einsum (57 s vs well under a second for 9M).
            q, k, v = q.transpose(1, 2), k.transpose(1, 2), v.transpose(1, 2)   # b h t d
            a = torch.softmax(torch.matmul(q, k.transpose(2, 3)) / (hd ** 0.5), -1)
            o = torch.matmul(a, v).transpose(1, 2).reshape(b, T, self.dim)
            h = h + o @ wo
            x = self.layer_norm(h, *self.ln[2 * i + 1])
            w1, w2, w3 = self.mlp[i]
            h = h + (torch.nn.functional.silu(x @ w1) * (x @ w2)) @ w3
        h = self.layer_norm(h, *self.ln[2 * layers])
        logits = h[:, -1] @ self.head_w + self.head_b
        return torch.log_softmax(logits, -1)


def sequences_for(board):
    moves = sc_engine.get_ordered_legal_moves(board)
    fen_tokens = tokenizer.tokenize(board.fen()).astype(np.int64)
    seqs = np.stack([np.concatenate([fen_tokens, [utils.MOVE_TO_ACTION[m.uci()], 0]]) for m in moves])
    return moves, seqs


def fp16_storage(src, dst):
    from onnx import helper, numpy_helper, TensorProto
    m = onnx.load(str(src)); g = m.graph
    inits, casts = [], []
    for init in list(g.initializer):
        if init.data_type == TensorProto.FLOAT and np.prod(init.dims) >= 1024:
            h = numpy_helper.from_array(numpy_helper.to_array(init).astype(np.float16), init.name + "_fp16")
            inits.append(h); casts.append(helper.make_node("Cast", [h.name], [init.name], to=TensorProto.FLOAT, name=init.name + "_cast"))
        else: inits.append(init)
    del g.initializer[:]; g.initializer.extend(inits)
    nodes = casts + list(g.node); del g.node[:]; g.node.extend(nodes)
    onnx.save(m, str(dst))


TEST_FENS = [
    chess.STARTING_FEN,
    "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
    "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4",   # Qxf7# available
    "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1",                                 # back-rank mate
    "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3",          # en passant legal
]

ONLY = ["9M"]
for model_name, (layers, dim, heads) in CONFIGS.items():
    if ONLY and model_name not in ONLY:
        continue
    r = report[model_name] = {"layers": layers, "dim": dim, "heads": heads}
    d = OUT / model_name; d.mkdir(exist_ok=True)
    try:
        progress(f"{model_name}: download")
        zpath = WORK / f"{model_name}.zip"
        if not zpath.exists():
            urllib.request.urlretrieve(f"https://storage.googleapis.com/searchless_chess/checkpoints/{model_name}.zip", zpath)
        ck = WORK / "checkpoints"; ck.mkdir(exist_ok=True)
        with zipfile.ZipFile(zpath) as z: z.extractall(ck)
        config = transformer.TransformerConfig(
            vocab_size=utils.NUM_ACTIONS, output_size=128,
            pos_encodings=transformer.PositionalEncodings.LEARNED,
            max_sequence_length=tokenizer.SEQUENCE_LENGTH + 2,
            num_heads=heads, num_layers=layers, embedding_dim=dim,
            apply_post_ln=True, apply_qk_layernorm=False, use_causal_mask=False)
        predictor = transformer.build_transformer_predictor(config=config)
        params = training_utils.load_parameters(
            checkpoint_dir=str(ck / model_name),
            params=predictor.initial_params(rng=jrandom.PRNGKey(1), targets=np.ones((1, 1), dtype=np.uint32)),
            step=6_400_000)
        r["param_keys"] = sorted(params.keys())[:12]
        jax_engine = neural_engines.ENGINE_FROM_POLICY["action_value"](
            return_buckets_values=bucket_values,
            predict_fn=neural_engines.wrap_predict_fn(predictor=predictor, params=params, batch_size=64))
        model = Searchless(params, layers, dim, heads).eval()

        worst, agree = 0.0, 0
        for fen in TEST_FENS:
            board = chess.Board(fen)
            moves, seqs = sequences_for(board)
            ref = np.asarray(jax_engine.analyse(board)["log_probs"])
            got = model(torch.tensor(seqs)).numpy()
            worst = max(worst, float(np.abs(ref - got).max()))
            agree += int(jax_engine.play(board) == moves[int(np.argmax(np.exp(got) @ bucket_values))])
        r["torch_vs_jax"] = worst; r["same_move"] = f"{agree}/{len(TEST_FENS)}"
        progress(f"{model_name}: torch vs jax {worst:.2e}, same move {agree}/{len(TEST_FENS)}")

        progress(f"{model_name}: export")
        dummy = torch.zeros(4, 79, dtype=torch.long)
        torch.onnx.export(model, (dummy,), str(d / "model.onnx"), input_names=["tokens"], output_names=["log_probs"],
                          dynamic_axes={"tokens": {0: "b"}, "log_probs": {0: "b"}}, opset_version=17,
                          do_constant_folding=True, dynamo=False)
        m = onnx.load(str(d / "model.onnx"), load_external_data=False)
        r["ops"] = sorted({n.op_type for n in m.graph.node}); r["ir"] = m.ir_version
        files = [("model.onnx", d / "model.onnx")]
        if (d / "model.onnx").stat().st_size > 250_000_000:
            fp16_storage(d / "model.onnx", d / "model_fp16.onnx")
            (d / "model.onnx").unlink()
            files = [("model_fp16.onnx", d / "model_fp16.onnx")]
        for label, path in files:
            so = ort.SessionOptions(); so.intra_op_num_threads = 1
            s = ort.InferenceSession(str(path), so, providers=["CPUExecutionProvider"])
            w2, agree2 = 0.0, 0
            for fen in TEST_FENS:
                board = chess.Board(fen)
                moves, seqs = sequences_for(board)
                ref = np.asarray(jax_engine.analyse(board)["log_probs"])
                got = s.run(None, {"tokens": seqs})[0]
                w2 = max(w2, float(np.abs(ref - got).max()))
                agree2 += int(jax_engine.play(board) == moves[int(np.argmax(np.exp(got) @ bucket_values))])
            _, seqs = sequences_for(chess.Board())
            t0 = time.perf_counter(); s.run(None, {"tokens": seqs}); ms = (time.perf_counter() - t0) * 1000
            r[label] = {"bytes": path.stat().st_size, "onnx_vs_jax": w2, "same_move": f"{agree2}/{len(TEST_FENS)}",
                        "start_position_ms_1thread": round(ms, 1)}
            progress(f"{model_name}: {label} {r[label]}")
        # Reference outputs for the app's parity test (9M only: small enough).
        if model_name == "9M":
            refs = []
            for fen in TEST_FENS:
                board = chess.Board(fen)
                moves, seqs = sequences_for(board)
                lp = np.asarray(jax_engine.analyse(board)["log_probs"])
                wp = np.exp(lp) @ bucket_values
                refs.append({"fen": fen, "fen_tokens": seqs[0][:77].tolist(),
                             "moves": [m.uci() for m in moves], "win_probs": [round(float(x), 6) for x in wp],
                             "best": jax_engine.play(board).uci()})
            (OUT / "reference_9M.json").write_text(json.dumps(refs))
        r["status"] = "ok"
    except Exception as e:
        r["status"] = "error: " + repr(e)[:400]; r["trace"] = traceback.format_exc()[-3000:]
        progress(f"{model_name}: FAILED {e!r}")
    finally:
        (OUT / "report.json").write_text(json.dumps(report, indent=1, default=str))
progress("done")
