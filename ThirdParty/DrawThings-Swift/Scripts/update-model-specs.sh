#!/usr/bin/env bash
#
# Refreshes the bundled model specification snapshot
# (Sources/DrawThingsClient/Resources/models.json) from the live list the Draw Things
# app downloads, so the client can resolve new models without a network request at
# runtime. Run before tagging a release; CI runs it on a schedule and opens a PR.
#
# Usage: Scripts/update-model-specs.sh [url]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${1:-https://models.drawthings.ai/models.json}"
DEST="$ROOT/Sources/DrawThingsClient/Resources/models.json"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

curl --fail --silent --show-error --location --max-time 60 "$URL" -o "$TMP"

# Validate and normalise: a JSON array of objects that all have a "file" key, written
# with stable formatting so diffs only show real changes.
python3 - "$TMP" "$DEST" <<'PY'
import json, sys
source, dest = sys.argv[1], sys.argv[2]
with open(source, encoding="utf-8") as f:
    specs = json.load(f)
if not isinstance(specs, list) or len(specs) < 100:
    sys.exit(f"error: expected a JSON array of model specs, got {type(specs).__name__} of length {len(specs) if isinstance(specs, list) else 'n/a'}")
missing = [i for i, spec in enumerate(specs) if not isinstance(spec, dict) or not isinstance(spec.get("file"), str)]
if missing:
    sys.exit(f"error: {len(missing)} entries have no 'file' key (first at index {missing[0]})")
try:
    with open(dest, encoding="utf-8") as f:
        previous = {spec["file"] for spec in json.load(f)}
except FileNotFoundError:
    previous = set()
current = {spec["file"] for spec in specs}
with open(dest, "w", encoding="utf-8") as f:
    json.dump(specs, f, indent=2, ensure_ascii=False)
    f.write("\n")
added, removed = sorted(current - previous), sorted(previous - current)
print(f"{len(specs)} specs ({len(added)} added, {len(removed)} removed)")
for name in added: print(f"  + {name}")
for name in removed: print(f"  - {name}")
PY
