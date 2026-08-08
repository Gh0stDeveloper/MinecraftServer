#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_config
printf '\n%-10s %-10s %-8s\n' INSTANCIA ESTADO PUERTO
printf '%-10s %-10s %-8s\n' '---------' '------' '------'
for i in "${INSTANCES[@]}"; do
  upper="${i^^}_PORT"; port="${!upper:-?}"
  systemctl is-active --quiet "bedrock@$i.service" 2>/dev/null && state=ONLINE || state=OFFLINE
  printf '%-10s %-10s %-8s\n' "$i" "$state" "$port"
done
printf '\nBDS: %s\nWeb: %s (puerto %s)\nDirección: %s:%s\n\n' "$(current_bds_version)" "$(systemctl is-active bedrock-web.service 2>/dev/null || true)" "$WEB_PORT" "$PUBLIC_HOST" "$LOBBY_PORT"
