#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"
APP="$ROOT/app"
UPLOADS="$ROOT/uploads"
REQUESTS="$UPLOADS/requests"
RESULTS="$ROOT/state/web-imports"
mkdir -p "$REQUESTS" "$RESULTS"

write_state(){
  local id="$1" state="$2" ok="$3" message="$4"
  python3 - "$RESULTS/$id.json" "$id" "$state" "$ok" "$message" <<'PY'
import json, os, sys, time
path, ident, state, ok, message = sys.argv[1:]
payload={"ok": ok.lower()=="true", "id":ident, "state":state, "message":message[-5000:], "updated_at":int(time.time())}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as f: json.dump(payload,f,ensure_ascii=False,separators=(",",":"))
os.replace(tmp,path)
PY
}

shopt -s nullglob
for req in "$REQUESTS"/*.json; do
  id="$(basename "$req" .json)"
  [[ "$id" =~ ^[0-9a-f]{32}$ ]] || { rm -f "$req"; continue; }
  processing="$REQUESTS/.${id}.processing"
  mv "$req" "$processing" 2>/dev/null || continue

  stored="$(python3 - "$processing" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1],encoding='utf-8')); print(d.get('stored_name',''))
except Exception: print('')
PY
)"
  if [[ ! "$stored" =~ ^[0-9a-f]{32}\.(zip|mcworld)$ || "${stored%%.*}" != "$id" ]]; then
    write_state "$id" failed false "Solicitud inválida."
    rm -f "$processing"
    continue
  fi

  file="$UPLOADS/$stored"
  real="$(realpath -m "$file")"
  case "$real" in "$UPLOADS"/*) ;; *) write_state "$id" failed false "Ruta de subida inválida."; rm -f "$processing"; continue;; esac
  if [[ ! -f "$real" ]]; then
    write_state "$id" failed false "El archivo subido ya no existe."
    rm -f "$processing"
    continue
  fi

  write_state "$id" importing true "Validando e importando Survival..."
  set +e
  output="$($APP/scripts/import-survival.sh "$real" 2>&1)"
  rc=$?
  if (( rc == 0 )); then
    safety="$($APP/scripts/check-survival-safety.sh "$ROOT/instances/survival/server.properties" 2>&1)"
    rc=$?
    output="$output\n$safety"
  fi
  if (( rc == 0 )); then
    systemctl start bedrock@survival.service
    sleep 2
    if systemctl is-active --quiet bedrock@survival.service; then
      write_state "$id" success true "$output\nSurvival iniciado correctamente."
    else
      logs="$(journalctl -u bedrock@survival.service -n 30 --no-pager 2>&1)"
      write_state "$id" failed false "$output\nEl mundo se importó, pero Survival no inició.\n$logs"
    fi
  else
    write_state "$id" failed false "$output"
  fi
  set -e
  rm -f "$real" "$processing"
done
