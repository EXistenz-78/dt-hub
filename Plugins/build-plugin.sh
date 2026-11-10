#!/bin/zsh
# build-plugin.sh NAME OUT_FOLDER
# Builds the plug-in in Plugins/NAME into OUT_FOLDER/NAME.dthubplugin (ad-hoc signed). Needs the Swift toolchain; run
# from anywhere. Each plug-in's Scripts/build.sh calls this with its own name.
#
# The identifier and the version are read from the plug-in's `DTHubManifest(...)` in its sources, so the bundle's
# Info.plist cannot say something else than the plug-in itself: a new version is written there, once.
# By convention the library is libNAME.dylib and the principal class NAMEEntry.
set -e
HERE="${0:A:h}"
NAME="${1:?usage: build-plugin.sh NAME OUT_FOLDER}"
OUT="${2:?usage: build-plugin.sh NAME OUT_FOLDER}"
PACKAGE="$HERE/$NAME"
[[ -f "$PACKAGE/Package.swift" ]] || { echo "build-plugin.sh: no plug-in named $NAME in $HERE" >&2; exit 1 }

# The first `id:` and `version:` after `DTHubManifest(`.
manifest_value() {
  cat "$PACKAGE/Sources/$NAME"/*.swift | perl -0ne 'print $1 if /DTHubManifest\(.*?\b'"$1"':\s*"([^"]+)"/s'
}
ID="$(manifest_value id)"
VERSION="$(manifest_value version)"
[[ -n "$ID" && -n "$VERSION" ]] || { echo "build-plugin.sh: no id or version in the DTHubManifest of $NAME" >&2; exit 1 }

mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
swift build -c release --package-path "$PACKAGE" --scratch-path "$SCRATCH" >/dev/null
"$HERE/../PluginKit/Scripts/make-bundle.sh" "$(find "$SCRATCH" -name "lib$NAME.dylib" -not -path '*.dSYM/*' | head -1)" \
  "$OUT/$NAME.dthubplugin" "$ID" "$NAME" "$VERSION" "${NAME}Entry"
echo "$OUT/$NAME.dthubplugin"
