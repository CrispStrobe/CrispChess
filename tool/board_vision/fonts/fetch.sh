#!/bin/sh
# Fonts the trainer renders chess glyphs from that are not system packages.
# Every one is under the SIL Open Font License 1.1 (see the README,
# "Training data licences"); the files are not committed.
set -e
cd "$(dirname "$0")"
get() { [ -s "$1" ] || curl -fsSL -o "$1" "$2"; }
# Noto Sans Symbols 2 — The Noto Project Authors.
get NotoSansSymbols2-Regular.ttf \
  https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansSymbols2/hinted/ttf/NotoSansSymbols2-Regular.ttf
# JuliaMono — The JuliaMono Project Authors (Cormullion).
get JuliaMono-Regular.ttf \
  https://github.com/cormullion/juliamono/raw/master/JuliaMono-Regular.ttf
# Fairfax HD — Kreative Software (Rebecca Bettencourt).
get FairfaxHD.ttf \
  https://github.com/kreativekorp/open-relay/raw/master/FairfaxHD/FairfaxHD.ttf
# GNU Unifont 15.1.05 — Roman Czyborra, Paul Hardy et al. Upstream builds
# since 13.0.04 are dual-licensed; this project uses the OFL 1.1 option (the
# Debian package's copyright file lists only the GPL, so fetch upstream).
get unifont-15.1.05.otf \
  https://unifoundry.com/pub/unifont/unifont-15.1.05/font-builds/unifont-15.1.05.otf
