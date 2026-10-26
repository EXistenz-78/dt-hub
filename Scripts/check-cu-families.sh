#!/usr/bin/env bash
# Confronta i conteggi delle istruzioni di Draw Things (upstream) con il port in DTBridge/ComputeUnits.
# Segnala: file mancanti (architetture nuove) e file cambiati (conteggio aggiornato upstream).
# Richiede `gh` autenticato. Uso: Scripts/check-cu-families.sh
set -euo pipefail
REPO="drawthingsai/draw-things-community"
DIR="Libraries/SwiftDiffusion/Sources/Models/InstructionCount"
LOCAL="$(cd "$(dirname "$0")/.." && pwd)/Packages/Sources/DTBridge/ComputeUnits"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Famiglie volutamente non portate (video, Kandinsky, Wurstchen…): niente stima per scelta.
SKIP=" HunyuanInstructionCount KandinskyInstructionCount LTX2InstructionCount MiniMaxH3InstructionCount WanInstructionCount WurstchenInstructionCount "

# Il corpo di un file senza l'intestazione "Ported from…" e con `public` tolto.
normalize() { grep -v '^// \(Ported from\|at drawthingsai\|visibility was lowered\)' "$1" | sed 's/^public func/func/' | grep -v '^$'; }

missing=0; changed=0
for name in $(gh api "repos/$REPO/contents/$DIR" --jq '.[].name' | sed 's/\.swift$//'); do
  [[ "$SKIP" == *" $name "* ]] && continue
  gh api "repos/$REPO/contents/$DIR/$name.swift" --jq .content | base64 -d > "$TMP/$name.swift"
  if [[ ! -f "$LOCAL/$name.swift" ]]; then
    echo "MANCA     $name  (architettura nuova: portare il file e aggiungere la famiglia a ComputeUnitsEstimator)"; missing=1
  elif ! diff -q <(normalize "$TMP/$name.swift") <(normalize "$LOCAL/$name.swift") >/dev/null; then
    echo "CAMBIATO  $name  (diff: diff <(…upstream) <(…locale))"; changed=1
  fi
done
# Anche la formula e le chiamate per famiglia stanno in ComputeUnits.swift: guarda se è cambiato dopo l'ultimo port.
PORTED=$(grep -ho 'commit [0-9a-f]\{40\}' "$LOCAL"/*.swift | sort | uniq -c | sort -rn | head -1 | awk '{print $3}')
HEAD_SHA=$(gh api "repos/$REPO/commits/HEAD" --jq .sha)
echo "Port fermo a ${PORTED:0:9}; upstream HEAD ${HEAD_SHA:0:9}."
(( missing || changed )) && exit 1
echo "Conteggi allineati."
