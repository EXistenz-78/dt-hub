#!/usr/bin/env bash
#
# Regenerates the protobuf, gRPC and FlatBuffers sources in
# Sources/DrawThingsClient/Generated, plus the gRPC server stubs the tests' in-process
# server uses (Tests/DrawThingsClientTests/Generated).
#
# The schemas (imageService.proto and config.fbs) are read from a local checkout of
# https://github.com/drawthingsai/draw-things-community; they are not stored in this
# repository.
#
# The protoc plugins are built from this package's resolved dependencies, so the
# generated code always matches the swift-protobuf / grpc-swift-protobuf runtime
# pinned in Package.resolved. Requires `protoc` and `flatc` (25.9.23) on PATH.
#
# Usage:
#   Scripts/generate.sh <path-to-draw-things-community>
#   DT_COMMUNITY=<path> Scripts/generate.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Sources/DrawThingsClient/Generated"
FLATC_VERSION="25.9.23"

COMMUNITY="${1:-${DT_COMMUNITY:-}}"
if [[ -z "$COMMUNITY" ]]; then
  echo "usage: Scripts/generate.sh <path-to-draw-things-community> (or set DT_COMMUNITY)" >&2
  exit 1
fi
PROTO_SOURCE="$COMMUNITY/Libraries/GRPC/Models/Sources/imageService/imageService.proto"
FBS_SOURCE="$COMMUNITY/Libraries/DataModels/Sources/config.fbs"
for schema in "$PROTO_SOURCE" "$FBS_SOURCE"; do
  [[ -f "$schema" ]] || { echo "error: $schema not found; is $COMMUNITY a draw-things-community checkout?" >&2; exit 1; }
done

# Work on temporary copies of the schemas.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROTOS="$TMP/protos"
mkdir -p "$PROTOS"
cp "$PROTO_SOURCE" "$FBS_SOURCE" "$PROTOS/"
echo "Using schemas from $COMMUNITY ($(git -C "$COMMUNITY" rev-parse --short HEAD 2>/dev/null || echo "not a git checkout"))"

command -v protoc >/dev/null || { echo "error: protoc not found" >&2; exit 1; }
command -v flatc >/dev/null || { echo "error: flatc not found" >&2; exit 1; }
if ! flatc --version | grep -q "$FLATC_VERSION"; then
  echo "error: flatc $FLATC_VERSION required (matches the FlatBuffers package pin), found: $(flatc --version)" >&2
  exit 1
fi

echo "Building protoc plugins from resolved dependencies..."
swift build --package-path "$ROOT" -c release --product protoc-gen-swift >/dev/null
swift build --package-path "$ROOT" -c release --product protoc-gen-grpc-swift-2 >/dev/null
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

mkdir -p "$OUT"
rm -f "$OUT"/imageService.pb.swift "$OUT"/imageService.grpc.swift "$OUT"/config_generated.swift

echo "Generating protobuf messages and gRPC client..."
protoc \
  --proto_path="$PROTOS" \
  --plugin=protoc-gen-swift="$BIN/protoc-gen-swift" \
  --plugin=protoc-gen-grpc-swift-2="$BIN/protoc-gen-grpc-swift-2" \
  --swift_opt=Visibility=Public \
  --swift_out="$OUT" \
  --grpc-swift-2_opt=Visibility=Internal,Server=false,Client=true \
  --grpc-swift-2_out="$OUT" \
  "$PROTOS/imageService.proto"

echo "Generating gRPC server stubs for the test server..."
TEST_OUT="$ROOT/Tests/DrawThingsClientTests/Generated"
mkdir -p "$TEST_OUT"
rm -f "$TEST_OUT"/imageService.grpc.swift
protoc \
  --proto_path="$PROTOS" \
  --plugin=protoc-gen-grpc-swift-2="$BIN/protoc-gen-grpc-swift-2" \
  --grpc-swift-2_opt=Visibility=Internal,Server=true,Client=false,ExtraModuleImports=DrawThingsClient \
  --grpc-swift-2_out="$TEST_OUT" \
  "$PROTOS/imageService.proto"

echo "Generating FlatBuffers configuration..."
# config.fbs is a Dflat schema: it uses the `primary` and `indexed` attributes,
# which Dflat declares itself. Declare them for plain flatc.
{ printf 'attribute "primary";\nattribute "indexed";\n'; cat "$PROTOS/config.fbs"; } > "$TMP/config.fbs"
flatc --swift --gen-object-api -o "$OUT" "$TMP/config.fbs"
# flatc does not emit Sendable, and Swift 6 only accepts a checked Sendable conformance
# in the declaring file, so add it to the (plain Int8) enums here.
sed -i '' -E 's/^(public enum [A-Za-z]+: Int8, Enum, Verifiable) \{/\1, Sendable {/' "$OUT/config_generated.swift"

echo "Done. Generated files:"
ls -1 "$OUT" "$TEST_OUT"
