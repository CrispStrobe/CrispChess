#!/bin/sh
# Pack what the Kaggle kernel needs into one archive for the private dataset
# <user>/crispchess-board-vision-src: the generator and trainer, the piece
# sets pre-rendered to PNG (no cairosvg there), the permissive fonts, and an
# optional benchmark directory to score on.
#
#   tool/board_vision/kaggle/build_dataset.sh OUT_DIR [BENCH_DIR]
#   KAGGLE_API_TOKEN=... kaggle datasets version -p OUT_DIR -m "update"
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
out=$1
bench=$2
[ -n "$out" ] || { echo "usage: $0 OUT_DIR [BENCH_DIR]"; exit 1; }
stage=$(mktemp -d "${out%/}.stage.XXXX")
mkdir -p "$out" "$stage/src/board_vision/fonts" "$stage/src/dejavu"
cp "$here"/*.py "$stage/src/board_vision/"
cp -r "$here/pieces" "$stage/src/board_vision/"
"$here/fonts/fetch.sh"
cp "$here"/fonts/*.ttf "$here"/fonts/*.otf "$stage/src/board_vision/fonts/"
for f in DejaVuSans.ttf DejaVuSans-Bold.ttf DejaVuSerif.ttf DejaVuSerif-Bold.ttf; do
  cp "/usr/share/fonts/truetype/dejavu/$f" "$stage/src/dejavu/"
done
python3 "$here/prerender.py" --out "$stage/src/pieces_png"
[ -n "$bench" ] && cp -r "$bench" "$stage/src/bench_v1"
tar czf "$out/src.tar.gz" -C "$stage" src
rm -rf "$stage"
cat > "$out/dataset-metadata.json" <<META
{
  "title": "crispchess-board-vision-src",
  "id": "${KAGGLE_USER:-chr1s4}/crispchess-board-vision-src",
  "licenses": [{"name": "other"}]
}
META
ls -la "$out"
