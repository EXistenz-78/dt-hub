#!/bin/bash
# Packages a Release build of DT Hub with the custom gRPCServerCLI inside it.
#
#   Scripts/package-release.sh <DT Hub.app> <server folder> <output folder>
#
# <server folder> holds gRPCServerCLI-macOS and its four *.bundle folders (the unzipped Custom-gRPCServerCLI.zip of a
# release, or a build of the fork). In the output folder it writes:
#   DT-Hub-<version>-macOS-arm64.zip   the app: what the in-app update downloads (the manifest names it)
#   DT-Hub-<version>-macOS-arm64.dmg   the app, an Applications link and the licence and notes of the server
# The app gets the server in Contents/Helpers and the licence, notes and patch in Contents/Resources/Server, and is
# signed again with the identity it was built with.
set -euo pipefail

if [ $# -ne 3 ]; then echo "usage: $0 <DT Hub.app> <server folder> <output folder>" >&2; exit 2; fi
APP_SRC="$1"; SERVER="$2"; OUT="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$APP_SRC" ] || { echo "no app at $APP_SRC" >&2; exit 1; }
[ -x "$SERVER/gRPCServerCLI-macOS" ] || { echo "no gRPCServerCLI-macOS in $SERVER" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dthub-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/DT Hub.app"
ditto "$APP_SRC" "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
[ -n "$IDENTITY" ] || { echo "the app is not signed: cannot tell which identity to sign with" >&2; exit 1; }

# The server and its resource bundles side by side, then the licence, notes and patch.
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/Server"
ditto "$SERVER/gRPCServerCLI-macOS" "$APP/Contents/Helpers/gRPCServerCLI-macOS"
for bundle in "$SERVER"/*.bundle; do ditto "$bundle" "$APP/Contents/Helpers/$(basename "$bundle")"; done
cp "$ROOT/Server/LICENSE.md" "$ROOT/Server/README.md" "$ROOT/Server/krea2-edit.patch" "$ROOT/docs/moss-image-edit-lora.md" \
  "$APP/Contents/Resources/Server/"
mv "$APP/Contents/Resources/Server/moss-image-edit-lora.md" "$APP/Contents/Resources/Server/MOSS-Image-Edit-LoRA-guide.md"

# Inside out: the program and the bundles, then the app (with the hardened runtime, as it was built).
codesign --force --sign "$IDENTITY" "$APP/Contents/Helpers/gRPCServerCLI-macOS"
for bundle in "$APP"/Contents/Helpers/*.bundle; do codesign --force --sign "$IDENTITY" "$bundle"; done
codesign --force --sign "$IDENTITY" --options runtime --preserve-metadata=entitlements "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$OUT"
NAME="DT-Hub-$VERSION-macOS-arm64"
rm -f "$OUT/$NAME.zip" "$OUT/$NAME.dmg"
ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"

# The disk image: the app, a link to Applications, and the server's licence and notes (the .md files) beside them.
STAGE="$WORK/dmg"
mkdir -p "$STAGE/Docs"
ditto "$APP" "$STAGE/DT Hub.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Server/LICENSE.md" "$STAGE/Docs/LICENSE.md"
cp "$ROOT/Server/README.md" "$STAGE/Docs/README.md"
cp "$ROOT/Server/krea2-edit.patch" "$STAGE/Docs/krea2-edit.patch"
cp "$ROOT/docs/moss-image-edit-lora.md" "$STAGE/Docs/MOSS-Image-Edit-LoRA-guide.md"
hdiutil create -quiet -volname "DT Hub $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$OUT/$NAME.dmg"

echo "$OUT/$NAME.zip"
echo "$OUT/$NAME.dmg"
