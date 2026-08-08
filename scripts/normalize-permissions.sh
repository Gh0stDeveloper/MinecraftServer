#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"
APP_DIR="$ROOT/app"

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo '[ERROR] Ejecuta con sudo/root.' >&2; exit 1; }
[[ -d "$APP_DIR" ]] || { echo "[ERROR] No existe $APP_DIR" >&2; exit 1; }

chown -R root:bedrock "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 0755 {} +
find "$APP_DIR" -type f -exec chmod 0644 {} +
chmod 0755 "$APP_DIR/mcserver" "$APP_DIR/install.sh"
find "$APP_DIR/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
[[ -f "$APP_DIR/scripts/bds-resolver.py" ]] && chmod 0755 "$APP_DIR/scripts/bds-resolver.py"

if [[ -d "$ROOT/scripts" ]]; then
  chown -R root:bedrock "$ROOT/scripts"
  find "$ROOT/scripts" -type d -exec chmod 0755 {} +
  find "$ROOT/scripts" -type f -exec chmod 0644 {} +
  find "$ROOT/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
  [[ -f "$ROOT/scripts/bds-resolver.py" ]] && chmod 0755 "$ROOT/scripts/bds-resolver.py"
fi

chmod 0755 "$ROOT" "$APP_DIR" "$APP_DIR/scripts"
echo '[OK] Permisos del código y scripts normalizados.'
