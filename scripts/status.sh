#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; source "$SCRIPT_DIR/lib.sh"; source "$SCRIPT_DIR/socket-check.sh"; source_config; source_engines
printf '\n%-10s %-8s %-10s %-8s\n' INSTANCIA MOTOR ESTADO PUERTO
printf '%-10s %-8s %-10s %-8s\n' '---------' '-----' '------' '------'
probe="$APP_DIR/scripts/bedrock-ping.py"; [[ -f "$probe" ]] || probe="$SCRIPT_DIR/bedrock-ping.py"
for i in "${INSTANCES[@]}"; do
  upper="${i^^}_PORT"; port="${!upper:-?}"; engine="$(engine_for "$i")"
  if [[ "$i" == survival && -f "$STATE_DIR/survival-pending-import" ]]; then
    state=PENDIENTE
  elif systemctl is-active --quiet "bedrock@$i.service" 2>/dev/null \
       && udp_port_listening "$port" \
       && python3 "$probe" "$port" >/dev/null 2>&1; then
    state=ONLINE
  elif systemctl is-active --quiet "bedrock@$i.service" 2>/dev/null; then
    state=DEGRADADO
  else
    state=OFFLINE
  fi
  printf '%-10s %-8s %-10s %-8s\n' "$i" "$engine" "$state" "$port"
done
printf '\nBDS: %s\nPowerNukkitX: %s\nGateway: %s\nWeb: %s (puerto %s)\nDirección: %s:%s\n\n' "$(current_bds_version)" "$(current_pnx_version)" "$(systemctl is-active bedrock-gateway.service 2>/dev/null || true)" "$(systemctl is-active bedrock-web.service 2>/dev/null || true)" "$WEB_PORT" "$PUBLIC_HOST" "$LOBBY_PORT"
