#!/usr/bin/env bash
# claude-mem-watchdog.sh
#
# Controlla se claude-mem e' bloccato per autenticazione e, se serve, riavvia il worker.
#
# Contesto: il worker legge il token di accesso (~8 ore) dalla keychain "Claude Code-credentials"
# all'avvio e a ogni nuova sessione, e non lo rinnova da solo. Se il token e' scaduto, ogni query
# fallisce con "OAuth session expired and could not be refreshed" finche' la keychain non viene
# aggiornata (di solito da un login o da Claude Code usato nel terminale).
#
# Uso:
#   claude-mem-watchdog.sh            solo diagnosi, non cambia nulla
#   claude-mem-watchdog.sh --restart  se il token in keychain e' valido ma il worker e' bloccato,
#                                     riavvia il worker
#   claude-mem-watchdog.sh --notify   mostra anche una notifica macOS quando serve intervenire
#
# Codici di uscita: 0 tutto ok | 1 worker riavviato (o da riavviare) | 2 serve login | 3 errore

set -u

DATA_DIR="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}"
KEYCHAIN_SERVICE="Claude Code-credentials"
DO_RESTART=0
DO_NOTIFY=0

for arg in "$@"; do
  case "$arg" in
    --restart) DO_RESTART=1 ;;
    --notify)  DO_NOTIFY=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Opzione sconosciuta: $arg" >&2; exit 3 ;;
  esac
done

say() { printf '%s\n' "$*"; }
notify() {
  [ "$DO_NOTIFY" -eq 1 ] || return 0
  osascript -e "display notification \"$1\" with title \"claude-mem\"" >/dev/null 2>&1 || true
}

command -v python3 >/dev/null || { say "python3 non trovato"; exit 3; }

# 1) Scadenza del token di accesso in keychain. Legge solo expiresAt, non stampa mai il token.
EXPIRES_MS="$(
  security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null |
  python3 -I -c 'import sys,json
try:
    print(int(json.load(sys.stdin)["claudeAiOauth"]["expiresAt"]))
except Exception:
    print("")'
)"

if [ -z "$EXPIRES_MS" ]; then
  say "Keychain: impossibile leggere la scadenza del token ($KEYCHAIN_SERVICE)."
  say "Esegui: claude auth login"
  notify "Token non leggibile: esegui claude auth login"
  exit 2
fi

NOW_MS=$(( $(date +%s) * 1000 ))
LEFT_MIN=$(( (EXPIRES_MS - NOW_MS) / 60000 ))

if [ "$LEFT_MIN" -le 0 ]; then
  say "Token di accesso SCADUTO da $(( -LEFT_MIN )) minuti."
  say "Serve rinnovarlo: esegui 'claude auth login' in un terminale, poi rilancia questo script con --restart."
  notify "Token scaduto: esegui claude auth login"
  exit 2
fi
say "Token di accesso valido, scade tra ${LEFT_MIN} minuti."

# 2) Stato dell'osservatore.
HEALTH="$DATA_DIR/observer-health.json"
BLOCKED="$(
  python3 -I - "$HEALTH" <<'PY'
import json, sys
try:
    h = json.load(open(sys.argv[1]))
except Exception:
    print("unknown"); raise SystemExit
err, ok = h.get("lastErrorAt") or 0, h.get("lastSuccessAt") or 0
kind = h.get("lastErrorKind")
print("yes" if kind == "auth_invalid" and err > ok else "no")
PY
)"

case "$BLOCKED" in
  no)      say "Worker: nessun errore di autenticazione aperto."; exit 0 ;;
  unknown) say "Worker: observer-health.json non leggibile, nessuna azione."; exit 3 ;;
esac

say "Worker bloccato per autenticazione (ultimo errore piu' recente dell'ultimo successo)."

if [ "$DO_RESTART" -ne 1 ]; then
  say "Il token in keychain e' valido: riavvia il worker con --restart."
  notify "Worker bloccato: rilancia con --restart"
  exit 1
fi

# 3) Riavvio del worker. La coda e' nel database, quindi i messaggi in attesa restano.
PID="$(python3 -I -c 'import json,sys
try:
    print(json.load(open(sys.argv[1]))["pid"])
except Exception:
    print("")' "$DATA_DIR/worker-heartbeat.json")"

if [ -n "$PID" ] && ps -p "$PID" -o command= 2>/dev/null | grep -q "worker-service"; then
  say "Arresto il worker (PID $PID)..."
  kill "$PID"
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
  kill -0 "$PID" 2>/dev/null && { say "Il worker non si e' fermato (PID $PID). Interrompo."; exit 3; }
else
  say "Nessun worker in esecuzione da fermare."
fi

# Sceglie la versione piu' recente del plugin installato.
PLUGIN_ROOT="$HOME/.claude/plugins/cache/thedotmack/claude-mem"
LATEST="$(ls -1 "$PLUGIN_ROOT" 2>/dev/null | sort -V | tail -1)"
SCRIPT="$PLUGIN_ROOT/$LATEST/scripts/worker-service.cjs"
BUN="$(command -v bun || echo "$HOME/.bun/bin/bun")"

[ -f "$SCRIPT" ] && [ -x "$BUN" ] || { say "worker-service.cjs o bun non trovati ($SCRIPT)"; exit 3; }

say "Avvio il worker $LATEST..."
nohup "$BUN" "$SCRIPT" --daemon >/dev/null 2>&1 &

PORT="$(python3 -I -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("CLAUDE_MEM_WORKER_PORT","37777"))
except Exception:
    print("37777")' "$DATA_DIR/settings.json")"

for _ in $(seq 1 15); do
  if curl -s -m 2 "http://127.0.0.1:${PORT}/api/readiness" | grep -q '"ready"'; then
    say "Worker pronto sulla porta ${PORT}."
    notify "Worker riavviato"
    exit 1
  fi
  sleep 1
done

say "Il worker non risulta pronto dopo 15 secondi. Controlla ~/.claude-mem/logs."
exit 3
