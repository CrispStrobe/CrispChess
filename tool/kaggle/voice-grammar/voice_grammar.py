"""Does blocking end-of-text until the grammar is complete fix grammar-
constrained chess-move recognition in CrispASR's Whisper decoder?

Builds the CrispASR CLI twice from the same clone: as is, and with the
end-of-text penalty in whisper_suppress_invalid_grammar enabled (upstream
whisper.cpp ships it commented out). Transcribes synthetic spoken moves
(Kokoro TTS, English and German) with per-position grammars listing only the
legal moves, with Whisper tiny and base, and reports each transcript.
"""
import glob, os, subprocess, sys, time, urllib.request, json
from pathlib import Path

OUT = Path("/kaggle/working"); W = Path("/kaggle/temp"); W.mkdir(exist_ok=True)
def log(m):
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)
    with open(OUT / "progress.txt", "a") as f: f.write(m + "\n")

data = next(p for p in [Path("/kaggle/input/crispchess-voice-test"),
                        Path("/kaggle/input/datasets/chr1s4/crispchess-voice-test")] if p.exists())
repo = W / "CrispASR"
subprocess.run(["git", "clone", "--depth", "1", "https://github.com/CrispStrobe/CrispASR.git", str(repo)], check=True)
os.chdir(repo)
subprocess.run("git submodule update --init --depth 1 || true", shell=True)

def build(tag):
    t0 = time.time()
    r = subprocess.run("cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF "
                       "-DCRISPASR_BUILD_TESTS=OFF -DCRISPASR_BUILD_SERVER=OFF > /dev/null && "
                       "cmake --build build -j4 --target crispasr-cli 2>&1 | tail -5", shell=True,
                       capture_output=True, text=True)
    log(f"build {tag}: {time.time() - t0:.0f}s {r.stdout[-400:]} {r.stderr[-400:]}")
    b = W / f"crispasr-{tag}"
    subprocess.run(["cp", "build/bin/crispasr", str(b)], check=True)
    return b

plain = build("plain")
src = Path("src/crispasr.cpp").read_text()
old_allow = """    //bool allow_eot = false;
    //for (const auto & stack : grammar.stacks) {
    //    if (stack.empty()) {
    //        allow_eot = true;
    //        break;
    //    }
    //}"""
old_pen = """    //if (!allow_eot) {
    //    logits[eot] -= params.grammar_penalty;
    //}"""
assert old_allow in src and old_pen in src, "patch anchors not found"
src = src.replace(old_allow, old_allow.replace("//", "")).replace(old_pen, old_pen.replace("//", ""))
Path("src/crispasr.cpp").write_text(src)
strict = build("strict")

models = {}
for m in ("tiny", "base"):
    p = W / f"ggml-{m}.bin"
    if not p.exists():
        urllib.request.urlretrieve(f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{m}.bin", p)
    models[m] = p

cases = [("en1", "e4e5_en", "en", "knight to f3"), ("en2", "e4e5_en", "en", "bishop c4"),
         ("en3", "start_en", "en", "e4"), ("en4", "castle_en", "en", "castles"),
         ("en5", "qxd8_en", "en", "queen takes d8"), ("de1", "e4e5_de", "de", "springer nach f3"),
         ("de2", "e4e5_de", "de", "läufer c4"), ("de3", "castle_de", "de", "kurze rochade")]
results = []
for binary, btag in ((plain, "plain"), (strict, "strict")):
    for m, mp in models.items():
        for wav, gram, lang, said in cases:
            for variant in ("", "_x"):
                cmd = [str(binary), "-m", str(mp), "-l", lang, "-f", str(data / f"{wav}.wav"), "-nt",
                       "--grammar", str(data / f"{gram}{variant}.gbnf"), "--grammar-rule", "root"]
                out = subprocess.run(cmd, capture_output=True, text=True, timeout=300).stdout.strip()
                results.append({"binary": btag, "model": m, "wav": wav, "grammar": gram + variant,
                                "said": said, "heard": out})
                log(f"{btag:6} {m:4} {wav} {gram+variant:13} said={said!r:22} heard={out!r}")
(OUT / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False))
log("done")
