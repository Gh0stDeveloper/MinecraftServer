#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; source "$SCRIPT_DIR/lib.sh"; source_config; source_engines
printf '\n%-10s %-8s %-10s %-8s\n' INSTANCIA MOTOR ESTADO PUERTO
printf '%-10s %-8s %-10s %-8s\n' '---------' '-----' '------' '------'
for i in "${INSTANCES[@]}"; do upper="${i^^}_PORT"; port="${!upper:-?}"; engine="$(engine_for "$i")"; systemctl is-active --quiet "bedrock@$i.service" 2>/dev/null && state=ONLINE || state=OFFLINE; printf '%-10s %-8s %-10s %-8s\n' "$i" "$engine" "$state" "$port"; done
printf '\nBDS: %s\nPowerNukkitX: %s\nWeb: %s (puerto %s)\nDirección: %s:%s\n\n' "$(current_bds_version)" "$(current_pnx_version)" "$(systemctl is-active bedrock-web.service 2>/dev/null || true)" "$WEB_PORT" "$PUBLIC_HOST" "$LOBBY_PORT"
