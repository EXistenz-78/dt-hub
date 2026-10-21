#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the Tiled Upscale plug-in into OUT_FOLDER/TiledUpscale.dthubplugin (ad-hoc signed). Needs the Swift toolchain;
# run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.1"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libTiledUpscale.dylib -not -path '*.dSYM/*' | head -1)" \
  "$OUT/TiledUpscale.dthubplugin" com.exiztenz.dthub.tiledupscale TiledUpscale "$VERSION" TiledUpscaleEntry
echo "$OUT/TiledUpscale.dthubplugin"
