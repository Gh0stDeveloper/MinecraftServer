#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"
APP_DIR="$ROOT/app"
BDS_DIR="$ROOT/bds"
RELEASES_DIR="$BDS_DIR/releases"
CURRENT_LINK="$BDS_DIR/current"
INSTANCES_DIR="$ROOT/instances"
BACKUP_DIR="$ROOT/backups"
STATE_DIR="$ROOT/state"
CONFIG_DIR="$ROOT/config"
CONFIG_FILE="$CONFIG_DIR/network.env"
CACHE_DIR="$ROOT/cache"
INSTANCES=(lobby survival pvp bedwars skywars)

log(){ printf '\033[1;36m[mcserver]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Ejecuta con sudo/root."; }

source_config(){
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
  SERVER_NAME="${SERVER_NAME:-Bedrock Network}"
  PUBLIC_HOST="${PUBLIC_HOST:-127.0.0.1}"
  LOBBY_PORT="${LOBBY_PORT:-19132}"
  SURVIVAL_PORT="${SURVIVAL_PORT:-19133}"
  PVP_PORT="${PVP_PORT:-19134}"
  BEDWARS_PORT="${BEDWARS_PORT:-19135}"
  SKYWARS_PORT="${SKYWARS_PORT:-19136}"
  WEB_PORT="${WEB_PORT:-8080}"
}

lock_manager(){
  mkdir -p /run/lock
  exec 9>/run/lock/bedrock-network.lock
  flock -n 9 || die "Ya existe otra operación administrativa en ejecución."
}

current_bds_version(){
  [[ -f "$STATE_DIR/bds-version" ]] && { cat "$STATE_DIR/bds-version"; return; }
  [[ -L "$CURRENT_LINK" ]] && { basename "$(readlink -f "$CURRENT_LINK")"; return; }
  printf 'none'
}

stop_network(){ local i; for i in "${INSTANCES[@]}"; do systemctl stop "bedrock@$i.service" 2>/dev/null || true; done; }
start_network(){ local i; for i in "${INSTANCES[@]}"; do systemctl start "bedrock@$i.service"; done; }
restart_network(){ stop_network; start_network; }

services_healthy(){
  local i failed=0
  sleep 2
  for i in "${INSTANCES[@]}"; do
    systemctl is-active --quiet "bedrock@$i.service" || { warn "$i no está activo."; failed=1; }
  done
  return "$failed"
}

assert_survival_safe(){
  "$APP_DIR/scripts/check-survival-safety.sh" "$INSTANCES_DIR/survival/server.properties"
}

install_units(){
  cp "$APP_DIR/systemd/bedrock@.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-backup-survival.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-backup-survival.timer" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-web.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-auto-update.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-auto-update.timer" /etc/systemd/system/
  systemctl daemon-reload
  local i
  for i in "${INSTANCES[@]}"; do systemctl enable "bedrock@$i.service" >/dev/null; done
  systemctl enable bedrock-backup-survival.timer bedrock-web.service >/dev/null
}
