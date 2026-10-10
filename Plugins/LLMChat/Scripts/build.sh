#!/bin/zsh
# build.sh OUT_FOLDER
# Builds the LLM Chat plug-in into OUT_FOLDER/LLMChat.dthubplugin (ad-hoc signed). Needs the Swift toolchain;
# run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build.sh OUT_FOLDER}"
VERSION="1.0"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$HERE/.." --scratch-path "$SCRATCH" >/dev/null
"$HERE/../../../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name libLLMChat.dylib -not -path '*.dSYM/*' | head -1)" \
  "$OUT/LLMChat.dthubplugin" com.exiztenz.dthub.llmchat LLMChat "$VERSION" LLMChatEntry
echo "$OUT/LLMChat.dthubplugin"
