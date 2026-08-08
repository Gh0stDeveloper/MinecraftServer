#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
require_root
lock_manager
REPO_ARCHIVE="https://github.com/Gh0stDeveloper/MinecraftServer/archive/refs/heads/main.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
log "Descargando la versión más reciente del proyecto..."
curl -fL --retry 3 --connect-timeout 15 "$REPO_ARCHIVE" -o "$TMP/project.tar.gz"
tar -xzf "$TMP/project.tar.gz" -C "$TMP"
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 'MinecraftServer-*' | head -n1)"
[[ -n "$SRC" ]] || die "No se pudo extraer el proyecto."
mkdir -p "$APP_DIR" "$ROOT/scripts" "$ROOT/addons"
rsync -a --delete --exclude='.git' --exclude='*.zip' --exclude='*.tar.gz' "$SRC/" "$APP_DIR/"
rsync -a --delete "$APP_DIR/scripts/" "$ROOT/scripts/"
rsync -a --delete "$APP_DIR/addons/" "$ROOT/addons/"
chmod +x "$APP_DIR/mcserver" "$APP_DIR/install.sh" "$ROOT/scripts"/*.sh "$ROOT/scripts/bds-resolver.py" 2>/dev/null || true
ln -sfn "$APP_DIR/mcserver" /usr/local/bin/mcserver
chown -R bedrock:bedrock "$APP_DIR" "$ROOT/scripts" "$ROOT/addons"
install_units
source_config
"$APP_DIR/scripts/render-lobby-config.sh" || warn "No se pudo regenerar la configuración del lobby."
for instance in lobby pvp bedwars skywars; do
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/$instance/server.properties" 2>/dev/null || true)"
  if [[ -n "$level" && -d "$INSTANCES_DIR/$instance/worlds/$level" && -d "$ROOT/addons/${instance}_bp" ]]; then
    "$APP_DIR/scripts/install-addon.sh" "$instance" "$ROOT/addons/${instance}_bp" || warn "No se pudo actualizar addon $instance."
    systemctl restart "bedrock@$instance.service" 2>/dev/null || true
  fi
done
systemctl restart bedrock-web.service 2>/dev/null || true
ok "Proyecto, addons desplegados y web actualizados desde main."
