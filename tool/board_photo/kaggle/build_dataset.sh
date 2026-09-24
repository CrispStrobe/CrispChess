#!/bin/sh
# Packs what the kernel needs besides the internet into the private dataset
# chr1s4/crispchess-board-photo-src: crops.py and real_labels.json (from
# tool/board_photo/py/make_real_labels.py). Kaggle uploads only a kernel's
# code_file, so shared code has to travel this way.
#
#   tool/board_photo/kaggle/build_dataset.sh /path/to/real_labels.json [create]
set -e
here=$(cd "$(dirname "$0")" && pwd)
stage=${BP_STAGE:-/mnt/volume1/tmp/board-photo-ds}
rm -rf "$stage" && mkdir -p "$stage"
cp "$here/../py/crops.py" "$stage/"
cp "$1" "$stage/real_labels.json"
cat > "$stage/dataset-metadata.json" <<META
{"title": "crispchess-board-photo-src", "id": "chr1s4/crispchess-board-photo-src",
 "licenses": [{"name": "other"}]}
META
if [ "$2" = create ]; then
  python3 -m kaggle datasets create -p "$stage"
else
  python3 -m kaggle datasets version -p "$stage" -m "update"
fi
