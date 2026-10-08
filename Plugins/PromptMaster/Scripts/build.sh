#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the Prompt Master plug-in into OUT_FOLDER/PromptMaster.dthubplugin (ad-hoc signed). Needs the Swift toolchain;
# run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.0"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libPromptMaster.dylib -not -path '*.dSYM/*' | head -1)" \
  "$OUT/PromptMaster.dthubplugin" com.exiztenz.dthub.promptmaster PromptMaster "$VERSION" PromptMasterEntry
echo "$OUT/PromptMaster.dthubplugin"
