"""Export the permissively licensed chess language models to ONNX and check them.

Runs on Kaggle (it needs internet for the Hub and more RAM than the VPS has).
Everything happens on the CPU: Kaggle's torch no longer supports the P100 it
usually assigns, and export does not need a GPU. For each model it writes
  /kaggle/working/<name>/model.onnx   (+ tokenizer files)
and one /kaggle/working/report.json with ops, IR/opset, sizes, the max
|torch - onnxruntime| logit difference, CPU latency, and the move each model
picks from the start position under legal-move-constrained decoding.

Only models whose licence allows redistribution are listed here.
"""
import json, os, shutil, subprocess, sys, time, traceback
from pathlib import Path

subprocess.run([sys.executable, "-m", "pip", "install", "-q", "onnx", "onnxruntime", "chess"], check=False)

import numpy as np, torch, onnx, onnxruntime as ort, chess
from huggingface_hub import snapshot_download
from transformers import AutoModelForCausalLM, AutoTokenizer

torch.set_grad_enabled(False)
OUT = Path("/kaggle/working")
MODELS = [
    # id,                       licence,      move format
    ("FlameF0X/ChessSLM",        "apache-2.0", "text"),
    ("TobiasLogic/ChessAggro",   "apache-2.0", "text"),
    ("mlabonne/chesspythia-70m", "apache-2.0", "text"),
    ("nsarrazin/chessformer",    "mit",        "uci-token"),
    ("TobiasLogic/chessmamba",   "mit",        "mamba-step"),
    # The permissively licensed entries of mlabonne's Chess LLM Arena.
    ("FlameF0X/ChessSLM-PM",            "apache-2.0", "text"),
    ("mlabonne/grandpythia-200k-70m",   "apache-2.0", "text"),
    ("bharathrajcl/chess_llama_68m",    "apache-2.0", "text"),
    ("nlpguy/smolchess-v2",             "apache-2.0", "text"),
    ("nlpguy/amdchess-v9",              "apache-2.0", "text"),
    ("DedeProGames/dialochess",         "mit",        "text"),
    ("DedeProGames/Chesser-248K-Mini",  "apache-2.0", "text"),
]

# Graphs above this size (fp32) also get an fp16-storage copy.
FP16_ABOVE_BYTES = 250_000_000

# Prompt formats scored on real games; {moves} is the game so far.
FORMATS = {
    "arena":   "1.e4 e5 2.Nf3",     # the Chess LLM Arena / ChessAggro training format
    "spaced":  "1. e4 e5 2. Nf3",   # PGN
    "plain":   "e4 e5 Nf3",
    "blind":   "1.",                # what the arena actually feeds: no history
}
report = {}

def fp16_storage(src, dst):
    """Weights stored as fp16, each followed by a Cast to fp32: half the
    download, and both the app's runtimes still compute in fp32."""
    from onnx import helper, numpy_helper, TensorProto
    m = onnx.load(str(src))
    g = m.graph
    new_inits, casts = [], []
    for init in list(g.initializer):
        if init.data_type == TensorProto.FLOAT and np.prod(init.dims) >= 1024:
            arr = numpy_helper.to_array(init).astype(np.float16)
            h = numpy_helper.from_array(arr, init.name + "_fp16")
            new_inits.append(h)
            casts.append(helper.make_node("Cast", [h.name], [init.name], to=TensorProto.FLOAT,
                                          name=init.name + "_cast"))
        else:
            new_inits.append(init)
    del g.initializer[:]
    g.initializer.extend(new_inits)
    nodes = casts + list(g.node)
    del g.node[:]
    g.node.extend(nodes)
    onnx.save(m, str(dst))


def lichess_games(n_per_user=6):
    """CC0 games of the lichess Maia bots (mostly club players' games against
    them), as lists of SAN moves. Measurement data only, never shipped."""
    import urllib.request, io, chess.pgn
    games = []
    for user in ("maia1", "maia5", "maia9"):
        url = f"https://lichess.org/api/games/user/{user}?max={n_per_user}&moves=true&clocks=false&evals=false&opening=false"
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/x-chess-pgn"})
            txt = urllib.request.urlopen(req, timeout=60).read().decode()
        except Exception as e:
            progress(f"lichess fetch {user} failed: {e!r}"); continue
        f = io.StringIO(txt)
        while (g := chess.pgn.read_game(f)) is not None:
            b = g.board(); sans = []
            for mv in g.mainline_moves():
                sans.append(b.san(mv)); b.push(mv)
            if len(sans) >= 20: games.append(sans)
    return games


def render(fmt, sans):
    """The game so far in [fmt], ending where the next move goes."""
    if fmt == "blind":
        return "1."
    parts = []
    for i, san in enumerate(sans):
        san = san.rstrip("+#")
        if i % 2 == 0:
            parts.append(f"{i // 2 + 1}.{san}" if fmt == "arena" else
                         f"{i // 2 + 1}. {san}" if fmt == "spaced" else san)
        else:
            parts.append(san)
    nxt = len(sans)
    if fmt in ("arena", "spaced") and nxt % 2 == 0:
        parts.append(f"{nxt // 2 + 1}." if fmt == "arena" else f"{nxt // 2 + 1}.")
        text = " ".join(parts)
        return text  # "... 3." -> next token is the move (arena: no space; spaced: " Nf3")
    return " ".join(parts)


def move_text(fmt, prompt, san):
    san = san.rstrip("+#")
    if fmt == "blind":
        return san
    if fmt == "arena" and prompt.endswith("."):
        return san
    return " " + san if prompt else san


def score_formats(model, tok, games, positions_per_game=6):
    """Per format: share of positions where the actual move is the model's
    top legal choice, and mean probability given to it among legal moves."""
    out = {}
    rng = np.random.default_rng(0)
    picks = []
    for gi, g in enumerate(games):
        plies = sorted(rng.choice(np.arange(2, min(len(g), 80)), size=min(positions_per_game, min(len(g), 80) - 2), replace=False))
        picks += [(gi, p) for p in plies]
    pad = tok.pad_token_id if tok.pad_token_id is not None else (tok.eos_token_id or 0)
    for fmt in FORMATS:
        top1 = 0; probs = []
        t0 = time.time()
        for gi, ply in picks:
            sans = games[gi][:ply]
            board = chess.Board()
            for s_ in sans: board.push_san(s_)
            actual = games[gi][ply]
            legal = [board.san(m) for m in board.legal_moves]
            prompt = render(fmt, sans)
            p_ids = tok(prompt, add_special_tokens=True).input_ids
            seqs = []
            for san in legal:
                full = tok(prompt + move_text(fmt, prompt, san), add_special_tokens=True).input_ids
                # The move's tokens are what follows the prompt's; recompute the
                # split on the full string to be robust to merges across it.
                k = len(p_ids)
                while k > 0 and full[:k] != p_ids[:k]: k -= 1
                seqs.append((full, k))
            L = max(len(f) for f, _ in seqs)
            ids = torch.full((len(seqs), L), pad, dtype=torch.long)
            mask = torch.zeros((len(seqs), L), dtype=torch.long)
            for i, (f, _) in enumerate(seqs):
                ids[i, :len(f)] = torch.tensor(f); mask[i, :len(f)] = 1
            lp = torch.log_softmax(model(input_ids=ids, attention_mask=mask, use_cache=False).logits.float(), -1)
            scores = []
            for i, (f, k) in enumerate(seqs):
                scores.append(sum(lp[i, j - 1, f[j]].item() for j in range(max(k, 1), len(f))))
            sc = np.array(scores); sc = np.exp(sc - sc.max()); sc /= sc.sum()
            ai = legal.index(actual)
            top1 += int(np.argmax(sc) == ai); probs.append(float(sc[ai]))
        out[fmt] = {"top1": round(top1 / len(picks), 4), "mean_prob": round(float(np.mean(probs)), 4),
                    "positions": len(picks), "secs": round(time.time() - t0, 1)}
        progress(f"   format {fmt}: {out[fmt]}")
    return out


TOKENIZER_PROBES = ["1.", "1.e4", "1.e4 e5 2.Nf3 Nc6 3.Bb5", "1. e4 e5 2. Nf3 Nc6 3. Bb5",
                    "e4 e5 Nf3 Nc6", " Nf3", " O-O", " exd8=Q", " Qxh7", "Bxf7",
                    "1.d4 d5 2.c4 e6 3.Nc3 Nf6 4.Bg5 Be7 5.e3 O-O 6.Nf3 Nbd7 7.Rc1",
                    "e2e4 e7e5 g1f3", "12.Nxe5 dxe5 13.Qh5+"]


def progress(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)
    with open(OUT / "progress.txt", "a") as f:
        f.write(msg + "\n")

def graph_info(path):
    m = onnx.load(str(path), load_external_data=False)
    return {
        "ir_version": m.ir_version,
        "opsets": {o.domain or "ai.onnx": o.version for o in m.opset_import},
        "ops": sorted({n.op_type for n in m.graph.node}),
        "inputs": [(i.name, i.type.tensor_type.elem_type,
                    [d.dim_param or d.dim_value for d in i.type.tensor_type.shape.dim]) for i in m.graph.input],
        "outputs": [o.name for o in m.graph.output],
        "bytes": sum(f.stat().st_size for f in Path(path).parent.glob("*") if f.suffix in (".onnx", ".data") or f.name.endswith(".onnx_data")),
    }

class LogitsOnly(torch.nn.Module):
    """input_ids -> logits, no KV cache. The explicit all-ones attention mask
    keeps transformers from probing for packed sequences with torch.diff,
    which has no ONNX equivalent."""
    def __init__(self, m):
        super().__init__(); self.m = m
    def forward(self, input_ids):
        return self.m(input_ids=input_ids, attention_mask=torch.ones_like(input_ids),
                      use_cache=False).logits

def ort_check(path, model, vocab, seq=32):
    """Max |torch - onnx| per sequence length. A traced graph that froze its
    causal mask at the example length matches only there, so test several."""
    so = ort.SessionOptions(); so.intra_op_num_threads = 1
    s = ort.InferenceSession(str(path), so, providers=["CPUExecutionProvider"])
    name = s.get_inputs()[0].name
    diffs = {}
    for n in (8, 16, 32, 128):
        ids = torch.randint(0, vocab, (1, n))
        ref = model(input_ids=ids, attention_mask=torch.ones_like(ids), use_cache=False).logits.numpy()
        got = s.run(None, {name: ids.numpy().astype(np.int64)})[0]
        diffs[n] = float(np.abs(ref - got).max())
    lat = {"diff_by_len": diffs}
    for n in (32, 128):
        x = torch.randint(0, vocab, (1, n)).numpy().astype(np.int64)
        s.run(None, {name: x}); t = time.perf_counter()
        for _ in range(5): s.run(None, {name: x})
        lat[f"seq{n}_ms_1thread"] = round((time.perf_counter() - t) / 5 * 1000, 1)
    return max(diffs.values()), lat

def text_move_choice(model, tok, prompt="1.", board_moves=""):
    """Score every legal SAN move by teacher-forced log-prob."""
    board = chess.Board(); best = None
    for san in board_moves.split(): board.push_san(san)
    for mv in board.legal_moves:
        san = board.san(mv).rstrip("+#")
        p = tok(prompt, return_tensors="pt").input_ids
        c = tok(prompt + san, return_tensors="pt").input_ids
        n = c.shape[1] - p.shape[1]
        if n <= 0: continue
        lp = torch.log_softmax(model(input_ids=c, use_cache=False).logits[0, :-1], -1)
        score = sum(lp[c.shape[1] - n - 1 + k, c[0, c.shape[1] - n + k]].item() for k in range(n))
        if best is None or score > best[1]: best = (san, score, n)
    return {"move": best[0], "logprob": round(best[1], 3), "tokens": best[2]}

def export_mamba(local, d, r):
    """ChessMamba as one incremental step: (move, ply, state) -> (heads, state).

    The model is recurrent, so the app feeds it one move at a time and keeps
    the state, instead of re-reading the game. is_start selects the learned
    start token for the very first step (no move yet); the initial state is
    zeros, which is what the model's own step(h_prev=None) uses.
    """
    import importlib.util
    sys.path.insert(0, str(local))
    spec = importlib.util.spec_from_file_location("chessmamba_model", local / "model.py")
    mm = importlib.util.module_from_spec(spec); spec.loader.exec_module(mm)
    cfg = json.loads((local / "config.json").read_text())
    net = mm.ChessMamba(dim=cfg["dim"], depth=cfg["depth"], state_dim=cfg["state_dim"],
                        expand=cfg["expand"], max_plies=cfg["max_plies"], use_checkpoint=False)
    ck = torch.load(local / "ckpt" / "model.pt", map_location="cpu", weights_only=False)
    sd = ck.get("model", ck.get("state_dict", ck)) if isinstance(ck, dict) else ck
    missing, unexpected = net.load_state_dict(sd, strict=False)
    r["load_missing"], r["load_unexpected"] = list(missing)[:10], list(unexpected)[:10]
    net.eval()
    r["params_M"] = round(sum(p.numel() for p in net.parameters()) / 1e6, 2)
    depth, inner, sdim = cfg["depth"], cfg["dim"] * cfg["expand"], cfg["state_dim"]

    class Step(torch.nn.Module):
        def __init__(self, n):
            super().__init__(); self.n = n
        def forward(self, from_sq, to_sq, promo, ply, is_start, state):
            n = self.n
            mv = n.from_embed(from_sq) + n.to_embed(to_sq) + n.promo_embed(promo)
            start = n.start_token.view(1, n.dim)
            x = is_start * start + (1 - is_start) * mv + n.pos_embed(torch.clamp(ply, max=n.max_plies))
            new = []
            for i, block in enumerate(n.blocks):
                x, h = block.step(x, state[i])
                new.append(h)
            x = n.norm_f(x)
            pol, pro, val = n._heads(x)
            return pol, pro, val, torch.stack(new)

    step = Step(net).eval()
    L = lambda v: torch.tensor([v], dtype=torch.long)
    zero = torch.zeros(depth, 1, inner, sdim)
    torch.onnx.export(step, (L(0), L(0), L(0), L(0), torch.ones(1, 1), zero), str(d / "model.onnx"),
        input_names=["from_sq", "to_sq", "promo", "ply", "is_start", "state"],
        output_names=["policy", "promo_logits", "value", "new_state"],
        opset_version=17, do_constant_folding=True, dynamo=False)
    r["onnx"] = graph_info(d / "model.onnx")
    r["state_shape"] = [depth, 1, inner, sdim]

    # Parity over a real game against the model's own incremental API.
    board = chess.Board(); moves = []
    for san in "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7 c4 c6 cxb5 axb5 Nc3 Bb7 Bg5 b4 Nb1 h6".split():
        moves.append(board.push_san(san))
    so = ort.SessionOptions(); so.intra_op_num_threads = 1
    sess = ort.InferenceSession(str(d / "model.onnx"), so, providers=["CPUExecutionProvider"])
    state, (pol_ref, _, _) = net.init_incremental()
    feed = lambda f, t, p, ply, st, h: {"from_sq": np.array([f], np.int64), "to_sq": np.array([t], np.int64),
        "promo": np.array([p], np.int64), "ply": np.array([ply], np.int64),
        "is_start": np.array([[st]], np.float32), "state": h}
    pol, _, _, h = sess.run(None, feed(0, 0, 0, 0, 1.0, zero.numpy()))
    worst = float(np.abs(pol - pol_ref.numpy()).max())
    t0 = time.perf_counter()
    for ply, mv in enumerate(moves, start=1):
        promo = {None: 0, chess.QUEEN: 1, chess.ROOK: 2, chess.BISHOP: 3, chess.KNIGHT: 4}[mv.promotion]
        state, (pol_ref, _, _) = net.step_move(mv.from_square, mv.to_square, promo, state)
        pol, pro, val, h = sess.run(None, feed(mv.from_square, mv.to_square, promo, ply, 0.0, h))
        worst = max(worst, float(np.abs(pol - pol_ref.numpy()).max()))
    r["max_abs_diff"] = worst
    r["latency"] = {"step_ms_1thread": round((time.perf_counter() - t0) / len(moves) * 1000, 2)}
    legal = {m.from_square * 64 + m.to_square: board.san(m) for m in board.legal_moves}
    best = max(legal, key=lambda i: pol[0, i])
    r["move_after_30_plies"] = {"move": legal[best], "value": float(val[0, 0])}
    pol0, _, _, _ = sess.run(None, feed(0, 0, 0, 0, 1.0, zero.numpy()))
    b0 = chess.Board(); l0 = {m.from_square * 64 + m.to_square: b0.san(m) for m in b0.legal_moves}
    r["start_move"] = {"move": l0[max(l0, key=lambda i: pol0[0, i])]}
    # Batched variant: expand several moves from the same (or different)
    # states in one call, so the search pays for the weights once per node
    # instead of once per child.
    B = 4
    torch.onnx.export(step, (L(0).repeat(B), L(0).repeat(B), L(0).repeat(B), L(0).repeat(B),
                             torch.zeros(B, 1), torch.zeros(depth, B, inner, sdim)),
        str(d / "model_batch.onnx"),
        input_names=["from_sq", "to_sq", "promo", "ply", "is_start", "state"],
        output_names=["policy", "promo_logits", "value", "new_state"],
        dynamic_axes={"from_sq": {0: "b"}, "to_sq": {0: "b"}, "promo": {0: "b"}, "ply": {0: "b"},
                      "is_start": {0: "b"}, "state": {1: "b"}, "policy": {0: "b"},
                      "promo_logits": {0: "b"}, "value": {0: "b"}, "new_state": {1: "b"}},
        opset_version=17, do_constant_folding=True, dynamo=False)
    r["onnx_batch"] = graph_info(d / "model_batch.onnx")
    sb = ort.InferenceSession(str(d / "model_batch.onnx"), so, providers=["CPUExecutionProvider"])
    kids = [m for m in board.legal_moves][:10]
    fb = {"from_sq": np.array([m.from_square for m in kids], np.int64),
          "to_sq": np.array([m.to_square for m in kids], np.int64),
          "promo": np.zeros(len(kids), np.int64),
          "ply": np.full(len(kids), 31, np.int64),
          "is_start": np.zeros((len(kids), 1), np.float32),
          "state": np.repeat(h, len(kids), axis=1)}
    pb, _, vb, hb = sb.run(None, fb)
    bworst = 0.0
    for i, m in enumerate(kids):
        p1, _, v1, h1 = sess.run(None, feed(m.from_square, m.to_square, 0, 31, 0.0, h))
        bworst = max(bworst, float(np.abs(pb[i] - p1[0]).max()), float(np.abs(hb[:, i] - h1[:, 0]).max()))
    t0 = time.perf_counter()
    for _ in range(5): sb.run(None, fb)
    r["batch"] = {"max_abs_diff_vs_single": bworst, "batch10_ms_1thread": round((time.perf_counter() - t0) / 5 * 1000, 2)}
    r["status"] = "ok"
    progress(f"ChessMamba batch: {r['batch']}")
    progress(f"ChessMamba: ok diff={worst:.2e} {r['latency']} start={r['start_move']} after30={r['move_after_30_plies']}")

# Set to a list of repo ids to re-run only those models.
ONLY: list[str] = []

GAMES = lichess_games()
progress(f"{len(GAMES)} lichess games for format scoring")

for repo, licence, fmt in MODELS:
    if ONLY and repo not in ONLY:
        continue
    name = repo.split("/")[1]; d = OUT / name; d.mkdir(exist_ok=True)
    r = report[name] = {"repo": repo, "licence": licence, "format": fmt}
    progress(f"{repo}: download")
    try:
        local = Path(snapshot_download(repo))
        r["files"] = sorted(str(p.relative_to(local)) for p in local.rglob("*") if p.is_file())
        cfg = json.loads((local / "config.json").read_text()) if (local / "config.json").exists() else {}
        r["architectures"] = cfg.get("architectures")
        for f in ("tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt", "special_tokens_map.json", "config.json", "README.md", "LICENSE"):
            if (local / f).exists(): shutil.copy(local / f, d / f)
        if cfg.get("architecture") == "ChessMamba":
            export_mamba(local, d, r)
            continue
        if not cfg.get("architectures"):
            r["status"] = "no transformers config; custom code, not exported"
            progress(f"{repo}: {r['status']}"); continue

        model = AutoModelForCausalLM.from_pretrained(
            local, torch_dtype=torch.float32, attn_implementation="eager").eval()
        r["params_M"] = round(sum(p.numel() for p in model.parameters()) / 1e6, 1)
        vocab = model.config.vocab_size
        tok = AutoTokenizer.from_pretrained(local)
        r["tokenizer_class"] = type(tok).__name__
        r["tokenizer_sample"] = tok.tokenize("1. e4 e5 2. Nf3 Nc6") if fmt == "text" else None
        # Reference encodings for the app's tokenizers: with and without the
        # special tokens the tokenizer adds by default.
        (d / "tokenizer_probes.json").write_text(json.dumps([
            {"text": t, "ids": tok(t, add_special_tokens=False).input_ids,
             "ids_default": tok(t).input_ids} for t in TOKENIZER_PROBES], indent=0))

        published = local / "onnx" / "model.onnx"
        if published.exists():
            # Published with KV-cache inputs; record it, but export a plain
            # no-cache graph, which is what the app's runtimes drive.
            r["published_onnx"] = graph_info(published)
        if True:
            progress(f"{repo}: export")
            torch.onnx.export(
                LogitsOnly(model).eval(), (torch.randint(0, vocab, (1, 16)),), str(d / "model.onnx"),
                input_names=["input_ids"], output_names=["logits"],
                dynamic_axes={"input_ids": {0: "batch", 1: "seq"}, "logits": {0: "batch", 1: "seq"}},
                opset_version=17, do_constant_folding=True, dynamo=False)
        model.eval()  # export must not leave dropout switched on for the reference
        r["onnx"] = graph_info(d / "model.onnx")
        if r["onnx"]["bytes"] > FP16_ABOVE_BYTES:
            fp16_storage(d / "model.onnx", d / "model_fp16.onnx")
            so16 = ort.SessionOptions(); so16.intra_op_num_threads = 1
            s16 = ort.InferenceSession(str(d / "model_fp16.onnx"), so16, providers=["CPUExecutionProvider"])
            x = torch.randint(0, vocab, (1, 24))
            ref = model(input_ids=x, attention_mask=torch.ones_like(x), use_cache=False).logits.numpy()
            got = s16.run(None, {s16.get_inputs()[0].name: x.numpy().astype(np.int64)})[0]
            r["fp16"] = {"bytes": (d / "model_fp16.onnx").stat().st_size,
                         "max_abs_diff": float(np.abs(ref - got).max())}
            progress(f"{repo}: fp16 storage {r['fp16']}")
        progress(f"{repo}: verify with onnxruntime")
        r["max_abs_diff"], r["latency"] = ort_check(d / "model.onnx", model, vocab)
        if r["max_abs_diff"] > 1e-3:
            progress(f"{repo}: traced graph off by {r['max_abs_diff']:.2e}; trying the dynamo exporter")
            r["traced"] = {"diff": r["max_abs_diff"], "latency": r["latency"]}
            try:
                subprocess.run([sys.executable, "-m", "pip", "install", "-q", "onnxscript"], check=False)
                seq = torch.export.Dim("seq", min=2, max=1024)
                ep = torch.onnx.export(LogitsOnly(model).eval(), (torch.randint(0, vocab, (1, 16)),),
                    dynamic_shapes={"input_ids": {1: seq}}, input_names=["input_ids"],
                    output_names=["logits"], opset_version=18, dynamo=True)
                ep.optimize(); ep.save(str(d / "model.onnx"))
                r["exporter"] = "dynamo"
                r["onnx"] = graph_info(d / "model.onnx")
                r["max_abs_diff"], r["latency"] = ort_check(d / "model.onnx", model, vocab)
            except Exception as e:
                r["dynamo_error"] = repr(e)[:800]
        progress(f"{repo}: diffs {r['latency'].get('diff_by_len')}")
        if fmt == "text":
            if GAMES:
                torch.set_num_threads(os.cpu_count() or 4)
                r["formats"] = score_formats(model, tok, GAMES)
                r["best_format"] = max(r["formats"], key=lambda f: r["formats"][f]["mean_prob"])
            r["start_move"] = text_move_choice(model, tok)
            r["ruy_lopez_move4"] = text_move_choice(model, tok, "1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 4.",
                                                     board_moves="e4 e5 Nf3 Nc6 Bb5 a6")
        else:
            ids = tok("", return_tensors="pt").input_ids if tok("").input_ids else torch.tensor([[tok.bos_token_id or 0]])
            logits = model(input_ids=ids, use_cache=False).logits[0, -1]
            legal = {m.uci() for m in chess.Board().legal_moves}
            vocab_map = tok.get_vocab()
            cands = [(logits[vocab_map[u]].item(), u) for u in legal if u in vocab_map]
            r["start_move"] = {"move": max(cands)[1] if cands else None, "legal_in_vocab": len(cands)}
        r["status"] = "ok"
        progress(f"{repo}: ok diff={r['max_abs_diff']:.2e} {r['latency']} start={r['start_move']}")
        del model
    except Exception as e:
        r["status"] = "error: " + repr(e)[:500]; r["trace"] = traceback.format_exc()[-3000:]
        progress(f"{repo}: FAILED {e!r}")
    finally:
        (OUT / "report.json").write_text(json.dumps(report, indent=1, default=str))

progress("done")
