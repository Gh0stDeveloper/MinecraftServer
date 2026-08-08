#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
lock_manager

REPO_ARCHIVE="https://github.com/Gh0stDeveloper/MinecraftServer/archive/refs/heads/main.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ui_banner "Actualización del proyecto"
ui_section "Código"
ui_run_task "Descargando la versión más reciente" curl -fsSL --retry 3 --connect-timeout 15 "$REPO_ARCHIVE" -o "$TMP/project.tar.gz"
ui_run_task "Extrayendo archivos del proyecto" tar -xzf "$TMP/project.tar.gz" -C "$TMP"
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 'MinecraftServer-*' | head -n1)"
[[ -n "$SRC" ]] || die "No se pudo extraer el proyecto."

mkdir -p "$APP_DIR" "$ROOT/scripts" "$ROOT/addons" "$ROOT/minigames"
rsync -a --delete --exclude='.git' --exclude='*.zip' --exclude='*.tar.gz' "$SRC/" "$APP_DIR/"
rsync -a --delete "$APP_DIR/scripts/" "$ROOT/scripts/"
rsync -a --delete "$APP_DIR/addons/" "$ROOT/addons/"
bash "$APP_DIR/scripts/normalize-permissions.sh" >/dev/null
ln -sfn "$APP_DIR/mcserver" /usr/local/bin/mcserver
chown -R bedrock:bedrock "$ROOT/addons"

ui_section "Servicios y minijuegos"
ui_run_task "Actualizando unidades systemd" bash -c 'source "$1"; install_units' _ "$APP_DIR/scripts/lib.sh"
source_config
source_engines
validate_engine_layout

for instance in lobby pvp bedwars skywars; do
  [[ "$(engine_for "$instance")" == bds ]] || continue
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/$instance/server.properties" 2>/dev/null || true)"
  if [[ -n "$level" && -d "$INSTANCES_DIR/$instance/worlds/$level" && -d "$ROOT/addons/${instance}_bp" ]]; then
    ui_run_task "Actualizando addon de $instance" bash "$APP_DIR/scripts/install-addon.sh" "$instance" "$ROOT/addons/${instance}_bp"
  fi
done

ui_run_task "Preparando estructura de minijuegos" bash "$APP_DIR/scripts/minigame-manager.sh" prepare
ui_run_task "Actualizando configuración del Lobby" bash "$APP_DIR/scripts/render-lobby-config.sh"
ui_run_task "Reiniciando panel web" systemctl restart bedrock-web.service
systemctl is-active --quiet bedrock-web.service || die "bedrock-web.service no quedó activo después de actualizar."

ui_section "Actualización completada"
ok "Proyecto, permisos, motores, minijuegos y web actualizados desde main."
ui_note "Para completar runtimes pendientes: sudo mcserver bootstrap"
