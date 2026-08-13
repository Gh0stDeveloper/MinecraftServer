#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root

set_env_value(){
  local file="$1" key="$2" value="$3" escaped
  mkdir -p "$(dirname "$file")"
  escaped="${value//\\/\\\\}"; escaped="${escaped//\"/\\\"}"
  escaped="${escaped//&/\\&}"; escaped="${escaped//|/\\|}"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

set_property(){
  local file="$1" key="$2" value="$3" escaped
  [[ -f "$file" ]] || die "Falta configuración de instancia: $file"
  escaped="${value//\\/\\\\}"; escaped="${escaped//&/\\&}"; escaped="${escaped//|/\\|}"
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

allowlist_empty(){
  python3 - "$1" <<'PY'
import json, sys
try:
    value = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if isinstance(value, list) and not value else 1)
PY
}

mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
  defaults="$APP_DIR/config/network.env"
  [[ -f "$defaults" ]] || defaults="$SCRIPT_DIR/../config/network.env"
  cp "$defaults" "$CONFIG_FILE"
fi

# Migra únicamente el nombre genérico histórico; una marca personalizada se
# conserva intacta. La descripción se guarda en la configuración persistente
# para que el gateway la publique como sub-MOTD tras futuras actualizaciones.
legacy_name="$(awk -F= '$1=="SERVER_NAME"{v=substr($0,index($0,"=")+1); gsub(/^[\047\"]|[\047\"]$/, "", v); print v; exit}' "$CONFIG_FILE")"
if [[ -z "$legacy_name" || "$legacy_name" == "Bedrock Network" ]]; then
  set_env_value "$CONFIG_FILE" SERVER_NAME "Nexora Network"
fi
if ! grep -q '^SERVER_DESCRIPTION=' "$CONFIG_FILE"; then
  set_env_value "$CONFIG_FILE" SERVER_DESCRIPTION "Survival, PvP, BedWars y SkyWars en una sola aventura"
fi

source_config

LOBBY_BACKEND_PORT="${LOBBY_BACKEND_PORT:-20132}"
SURVIVAL_BACKEND_PORT="${SURVIVAL_BACKEND_PORT:-20133}"
LOBBY_BACKEND_PORTV6="${LOBBY_BACKEND_PORTV6:-20152}"
SURVIVAL_BACKEND_PORTV6="${SURVIVAL_BACKEND_PORTV6:-20153}"
for pair in \
  "TRANSFER_HOST_MODE:$TRANSFER_HOST_MODE" \
  "LOBBY_BACKEND_PORT:$LOBBY_BACKEND_PORT" \
  "SURVIVAL_BACKEND_PORT:$SURVIVAL_BACKEND_PORT" \
  "LOBBY_BACKEND_PORTV6:$LOBBY_BACKEND_PORTV6" \
  "SURVIVAL_BACKEND_PORTV6:$SURVIVAL_BACKEND_PORTV6"; do
  key="${pair%%:*}"; value="${pair#*:}"
  grep -q "^${key}=" "$CONFIG_FILE" || set_env_value "$CONFIG_FILE" "$key" "$value"
done

for instance in lobby survival; do
  template="$APP_DIR/instances/$instance/server.properties"
  [[ -f "$template" ]] || template="$SCRIPT_DIR/../instances/$instance/server.properties"
  target="$INSTANCES_DIR/$instance/server.properties"
  mkdir -p "$(dirname "$target")"
  [[ -f "$target" ]] || cp "$template" "$target"
done

set_property "$INSTANCES_DIR/lobby/server.properties" server-name "$SERVER_NAME | Lobby"
set_property "$INSTANCES_DIR/lobby/server.properties" server-port "$LOBBY_BACKEND_PORT"
set_property "$INSTANCES_DIR/lobby/server.properties" server-portv6 "$LOBBY_BACKEND_PORTV6"
set_property "$INSTANCES_DIR/lobby/server.properties" transport raknet
set_property "$INSTANCES_DIR/lobby/server.properties" enable-lan-visibility false

set_property "$INSTANCES_DIR/survival/server.properties" server-name "$SERVER_NAME | Survival"
set_property "$INSTANCES_DIR/survival/server.properties" server-port "$SURVIVAL_BACKEND_PORT"
set_property "$INSTANCES_DIR/survival/server.properties" server-portv6 "$SURVIVAL_BACKEND_PORTV6"
set_property "$INSTANCES_DIR/survival/server.properties" transport raknet
set_property "$INSTANCES_DIR/survival/server.properties" enable-lan-visibility false

# Una allowlist vacía bloquea a todos y no protege los logros. Solo se desactiva
# en ese caso; una allowlist poblada por el administrador se respeta.
survival_props="$INSTANCES_DIR/survival/server.properties"
survival_allowlist="$INSTANCES_DIR/survival/allowlist.json"
if grep -Eq '^allow-list=true([[:space:]]*)$' "$survival_props" \
   && [[ -f "$survival_allowlist" ]] && allowlist_empty "$survival_allowlist"; then
  set_property "$survival_props" allow-list false
  warn "Survival tenía allow-list=true con allowlist.json vacío; se desactivó para evitar bloquear a todos."
fi

if id bedrock >/dev/null 2>&1; then
  chown bedrock:bedrock \
    "$INSTANCES_DIR/lobby/server.properties" \
    "$INSTANCES_DIR/survival/server.properties"
  chown root:bedrock "$CONFIG_FILE"
  chmod 0640 "$CONFIG_FILE"
fi

ok "Entradas públicas UDP/$LOBBY_PORT y UDP/$SURVIVAL_PORT preparadas mediante gateway."
ok "Backends BDS: Lobby UDP/$LOBBY_BACKEND_PORT · Survival UDP/$SURVIVAL_BACKEND_PORT."
