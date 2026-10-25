#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the Panorama 360 plug-in into OUT_FOLDER/Panorama360.dthubplugin (ad-hoc signed). Needs the Swift
# toolchain; run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.0"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libPanorama360.dylib -not -path '*.dSYM/*' | head -1)" \
  "$OUT/Panorama360.dthubplugin" com.exiztenz.dthub.panorama360 Panorama360 "$VERSION" Panorama360Entry
echo "$OUT/Panorama360.dthubplugin"
