"""Voice moves on CrispASR TTS speech: which recogniser picks the right move?

Builds CrispASR (v0.8.37, the first release with grammar_strict and
whisper_score_texts) as a shared library, then for every synthetic utterance (Piper and
Kokoro voices, English and German, 13 chess moves each) and Whisper
tiny/base/small compares:
  free    unconstrained transcript, matched to a legal move
  strict  grammar-constrained decoding, end-of-text blocked until complete
  sum     argmax over legal phrases of log P(phrase | audio)
  mean    the same, per token (length-normalised)
  *_p     scoring with a priming prompt ("Chess moves: knight f3, ...")
"""
import ctypes, json, os, re, subprocess, time, wave
from array import array
from pathlib import Path

ENV = os.environ.get
OUT = Path(ENV("VOICE_OUT", "/kaggle/working")); W = Path(ENV("VOICE_OUT", "/kaggle/temp")); W.mkdir(exist_ok=True)
def log(m):
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)
    with open(OUT / "progress.txt", "a") as f: f.write(m + "\n")

# Local smoke test: VOICE_DATA, VOICE_REPO (prebuilt), VOICE_MODELS, VOICE_LIMIT.
data = Path(ENV("VOICE_DATA")) if ENV("VOICE_DATA") else next(p for p in [Path("/kaggle/input/crispchess-voice-eval"),
                        Path("/kaggle/input/datasets/chr1s4/crispchess-voice-eval")] if p.exists())
# The first release with grammar_strict + whisper_score_texts (CRISPASR_REF to override).
REF = ENV("CRISPASR_REF", "v0.8.37")
repo = Path(ENV("VOICE_REPO", W / "CrispASR"))
sh = lambda c, **k: subprocess.run(c, shell=True, check=True, **k)
if not ENV("VOICE_REPO"): sh(f"git clone -q --depth 1 --branch {REF} https://github.com/CrispStrobe/CrispASR.git {repo} "
                             f"&& cd {repo} && git submodule update --init --depth 1")
t0 = time.time()
if not ENV("VOICE_REPO"): sh(f"cd {repo} && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON "
   "-DCRISPASR_BUILD_TESTS=OFF -DCRISPASR_BUILD_SERVER=OFF > /dev/null "
   "&& cmake --build build -j4 --target crispasr-cli 2>&1 | tail -2")
log(f"built in {time.time() - t0:.0f}s")
libdir = [str(repo / "build/ggml/src"), str(repo / "build/src")]
for d in libdir:  # load ggml first so libcrispasr's dependencies resolve
    for so in sorted(Path(d).glob("*.so")):
        ctypes.CDLL(str(so), mode=ctypes.RTLD_GLOBAL)
L = ctypes.CDLL(str(repo / "build/src/libcrispasr.so"))
P, C = ctypes.c_void_p, ctypes.c_char_p
L.crispasr_session_open_explicit.restype = P
L.crispasr_session_open_explicit.argtypes = [C, C, ctypes.c_int]
L.crispasr_session_transcribe_lang.restype = P
L.crispasr_session_transcribe_lang.argtypes = [P, ctypes.POINTER(ctypes.c_float), ctypes.c_int, C]
L.crispasr_session_result_n_segments.argtypes = [P]
L.crispasr_session_result_segment_text.restype = C
L.crispasr_session_result_segment_text.argtypes = [P, ctypes.c_int]
L.crispasr_session_result_free.argtypes = [P]
L.crispasr_session_set_grammar_text.argtypes = [P, C, C, ctypes.c_float]
L.crispasr_session_set_grammar_strict.argtypes = [P, ctypes.c_int]
L.crispasr_session_score_texts.argtypes = [P, ctypes.POINTER(ctypes.c_float), ctypes.c_int, C, C,
                                           ctypes.POINTER(C), ctypes.c_int,
                                           ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_int)]
L.crispasr_session_close.argtypes = [P]

def pcm_of(path):
    with wave.open(str(path)) as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
        a = array("h", w.readframes(w.getnframes()))
    return (ctypes.c_float * len(a))(*[x / 32768.0 for x in a]), len(a)

def transcribe(s, pcm, lang):
    r = L.crispasr_session_transcribe_lang(s, pcm[0], pcm[1], lang.encode())
    if not r: return ""
    t = " ".join(L.crispasr_session_result_segment_text(r, i).decode("utf-8", "replace")
                 for i in range(L.crispasr_session_result_n_segments(r)))
    L.crispasr_session_result_free(r)
    return t.strip()

def norm(t):  # normalizeUtterance in lib/voice/spoken_moves.dart
    t = re.sub(r'[.,!?;:"“”„()]', " ", t.lower()).replace("-", " ")
    t = re.sub(r"([a-h])\s+([1-8])", r"\1\2", t)
    return re.sub(r"\s+", " ", t).strip()

def match(heard, phrases):  # matchUtterance
    t = norm(heard)
    if not t: return None
    for uci, ps in phrases.items():
        if any(norm(p) == t for p in ps): return uci
    best, hits = 0, set()
    for uci, ps in phrases.items():
        for p in ps:
            n = norm(p)
            if not n or not t.endswith(" " + n): continue
            if len(n) > best: best, hits = len(n), {uci}
            elif len(n) == best: hits.add(uci)
    return hits.pop() if len(hits) == 1 else None

PRIME = {"en": "Chess moves: knight f3, bishop c4, e4, castles kingside.",
         "de": "Schachzüge: Springer f3, Läufer c4, e4, kurze Rochade."}

def score(s, pcm, lang, texts, prompt):
    arr = (C * len(texts))(*[t.encode() for t in texts])
    lp = (ctypes.c_float * len(texts))(); nt = (ctypes.c_int * len(texts))()
    rc = L.crispasr_session_score_texts(s, pcm[0], pcm[1], lang.encode(),
                                        prompt.encode() if prompt else None, arr, len(texts), lp, nt)
    assert rc == 0, f"score_texts rc={rc}"
    return list(lp), list(nt)

def pick(owners, vals):
    best = {}
    for o, v in zip(owners, vals): best[o] = max(best.get(o, -1e30), v)
    return max(best, key=best.get)

cases = {(c["n"], c["lang"]): c for c in json.loads((data / "cases.json").read_text())}
voices = ENV("VOICE_VOICES", "").split() or sorted(p.name for p in (data / "audio").iterdir())
results = []
for m in ENV("VOICE_MODELS", "tiny base small").split():
    mp = W / f"ggml-{m}.bin"
    if not mp.exists(): sh(f"curl -sL -o {mp} https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{m}.bin")
    s = L.crispasr_session_open_explicit(str(mp).encode(), b"whisper", int(ENV("VOICE_THREADS", 4)))
    assert s, "open failed"
    for v in voices:
        lang = "de" if v.startswith(("kokoro_d", "piper_thorsten", "piper_kerstin")) else "en"
        for wav in sorted((data / "audio" / v).glob("*.wav"), key=lambda p: int(p.stem))[:int(ENV("VOICE_LIMIT", 99))]:
            c = cases[(int(wav.stem), lang)]
            pcm = pcm_of(wav)
            row = {"model": m, "voice": v, "n": c["n"], "lang": lang, "said": c["said"], "want": c["want"],
                   "n_texts": len(c["texts"])}
            t = time.time(); row["free_heard"] = transcribe(s, pcm, lang)
            row["free"] = match(row["free_heard"], c["phrases"]); row["t_free"] = time.time() - t
            L.crispasr_session_set_grammar_text(s, c["grammar"].encode(), b"root", 100.0)
            L.crispasr_session_set_grammar_strict(s, 1)
            t = time.time(); row["strict_heard"] = transcribe(s, pcm, lang)
            row["strict"] = match(row["strict_heard"], c["phrases"]); row["t_strict"] = time.time() - t
            L.crispasr_session_set_grammar_strict(s, 0)
            L.crispasr_session_set_grammar_text(s, None, None, 100.0)
            for tag, prompt in (("", None), ("_p", PRIME[lang])):
                t = time.time(); lp, nt = score(s, pcm, lang, c["texts"], prompt)
                row["t_score" + tag] = time.time() - t
                row["sum" + tag] = pick(c["owners"], lp)
                row["mean" + tag] = pick(c["owners"], [a / max(1, b) for a, b in zip(lp, nt)])
            results.append(row)
            ok = " ".join(f"{k}={'Y' if row[k] == c['want'] else row[k]}"
                          for k in ("free", "strict", "sum", "mean", "sum_p", "mean_p"))
            log(f"{m:5} {v:18} {c['n']:2} {c['said']!r:22} {ok}  "
                f"free={row['free_heard']!r} t={row['t_score']:.1f}s/{row['t_score_p']:.1f}s")
            (OUT / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False))
    L.crispasr_session_close(s)
    for k in ("free", "strict", "sum", "mean", "sum_p", "mean_p"):
        rs = [r for r in results if r["model"] == m]
        log(f"SUMMARY {m} {k:7} {sum(r[k] == r['want'] for r in rs)}/{len(rs)}")
log("done")
