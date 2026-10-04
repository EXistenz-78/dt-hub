#!/bin/zsh
# build-sample.sh OUT_FOLDER [b]
# Builds the sample plug-in of Examples/Sample into OUT_FOLDER/Sample.dthubplugin; with `b`, the second sample
# (identifier com.example.dthub.sample.b, other module and class) into OUT_FOLDER/SampleB.dthubplugin.
# Version 1.3. Needs the Swift toolchain; run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build-sample.sh OUT_FOLDER [b]}"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
if [[ "$2" == "b" ]]; then
  SAMPLE_B=1 swift build --package-path "$HERE/../Examples/Sample" --scratch-path "$SCRATCH" >/dev/null
  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePluginB.dylib | head -1)" "$OUT/SampleB.dthubplugin" com.example.dthub.sample.b SampleB 1.3 SampleBEntry
  echo "$OUT/SampleB.dthubplugin"
else
  swift build --package-path "$HERE/../Examples/Sample" --scratch-path "$SCRATCH" >/dev/null
  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePlugin.dylib | head -1)" "$OUT/Sample.dthubplugin" com.example.dthub.sample Sample 1.3 SampleEntry
  echo "$OUT/Sample.dthubplugin"
fi
