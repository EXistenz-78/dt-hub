#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the Flux3 Editing plug-in into OUT_FOLDER/Flux3Editing.dthubplugin (ad-hoc signed). Needs the Swift
# toolchain; run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.0"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libFlux3Editing.dylib -not -path '*.dSYM/*' | head -1)" \
  "$OUT/Flux3Editing.dthubplugin" com.exiztenz.dthub.flux3editing Flux3Editing "$VERSION" Flux3EditingEntry
echo "$OUT/Flux3Editing.dthubplugin"
