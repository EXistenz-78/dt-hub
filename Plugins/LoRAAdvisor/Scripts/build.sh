#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the LoRA Advisor plug-in into OUT_FOLDER/LoRAAdvisor.dthubplugin (ad-hoc signed). Needs the Swift toolchain;
# run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.2"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libLoRAAdvisor.dylib -not -path '*.dSYM/*' | head -1)" \
  "$OUT/LoRAAdvisor.dthubplugin" com.exiztenz.dthub.loraadvisor LoRAAdvisor "$VERSION" LoRAAdvisorEntry
echo "$OUT/LoRAAdvisor.dthubplugin"
