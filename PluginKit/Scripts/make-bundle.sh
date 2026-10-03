#!/bin/zsh
# make-bundle.sh DYLIB OUT.dthubplugin IDENTIFIER NAME VERSION PRINCIPAL_CLASS [CONTRACT]
# Wraps the dynamic library a plug-in package builds into a .dthubplugin bundle and signs it ad hoc.
set -e
DYLIB="$1"; OUT="$2"; ID="$3"; NAME="$4"; VERSION="$5"; CLASS="$6"; CONTRACT="${7:-1}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp "$DYLIB" "$OUT/Contents/MacOS/$NAME"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$ID</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>NSPrincipalClass</key><string>$CLASS</string>
<key>DTHubContract</key><integer>$CONTRACT</integer>
</dict></plist>
PLIST
codesign -s - --force "$OUT" >/dev/null 2>&1
