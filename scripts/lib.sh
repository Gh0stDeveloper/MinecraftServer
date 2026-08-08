#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"
APP_DIR="$ROOT/app"
BDS_DIR="$ROOT/bds"
RELEASES_DIR="$BDS_DIR/releases"
CURRENT_LINK="$BDS_DIR/current"
PNX_DIR="$ROOT/pnx"
PNX_RELEASES_DIR="$PNX_DIR/releases"
PNX_CURRENT_LINK="$PNX_DIR/current"
INSTANCES_DIR="$ROOT/instances"
BACKUP_DIR="$ROOT/backups"
STATE_DIR="$ROOT/state"
CONFIG_DIR="$ROOT/config"
CONFIG_FILE="$CONFIG_DIR/network.env"
ENGINES_FILE="$CONFIG_DIR/engines.env"
CACHE_DIR="$ROOT/cache"
INSTANCES=(lobby survival pvp bedwars skywars)

log(){ printf '\033[1;36m[mcserver]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Ejecuta con sudo/root."; }
source_config(){
  local defaults="$APP_DIR/config/network.env"
  [[ -f "$defaults" ]] || defaults="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/network.env"
  [[ -f "$defaults" ]] && source "$defaults"
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
  SERVER_NAME="${SERVER_NAME:-Bedrock Network}"
  PUBLIC_IP="${PUBLIC_IP:-}"
  PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-}"
  PUBLIC_HOST="${PUBLIC_HOST:-${PUBLIC_IP:-127.0.0.1}}"
  LOBBY_PORT="${LOBBY_PORT:-19132}"
  SURVIVAL_PORT="${SURVIVAL_PORT:-19133}"
  PVP_PORT="${PVP_PORT:-19134}"
  BEDWARS_PORT="${BEDWARS_PORT:-19135}"
  SKYWARS_PORT="${SKYWARS_PORT:-19136}"
  WEB_PORT="${WEB_PORT:-8080}"
  WEB_MAX_UPLOAD_MB="${WEB_MAX_UPLOAD_MB:-4096}"
}
source_engines(){ local defaults="$APP_DIR/config/engines.env"; [[ -f "$defaults" ]] || defaults="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/engines.env"; [[ -f "$defaults" ]] && source "$defaults"; [[ -f "$ENGINES_FILE" ]] && source "$ENGINES_FILE"; LOBBY_ENGINE="${LOBBY_ENGINE:-bds}"; SURVIVAL_ENGINE="${SURVIVAL_ENGINE:-bds}"; PVP_ENGINE="${PVP_ENGINE:-pnx}"; BEDWARS_ENGINE="${BEDWARS_ENGINE:-pnx}"; SKYWARS_ENGINE="${SKYWARS_ENGINE:-pnx}"; PNX_DOWNLOAD_URL="${PNX_DOWNLOAD_URL:-https://github.com/PowerNukkitX/PowerNukkitX/releases/download/snapshot/powernukkitx-shaded.jar}"; PNX_EXPECTED_MINECRAFT="${PNX_EXPECTED_MINECRAFT:-26.40}"; PNX_JAVA_MIN="${PNX_JAVA_MIN:-21}"; PNX_HEAP_MIN="${PNX_HEAP_MIN:-512M}"; PNX_HEAP_MAX="${PNX_HEAP_MAX:-2G}"; MANAGED_PLUGINS="${MANAGED_PLUGINS:-true}"; }
engine_for(){ source_engines; local instance="$1" var="${1^^}_ENGINE"; printf '%s' "${!var:-bds}"; }
instances_by_engine(){
  local wanted="$1" i
  for i in "${INSTANCES[@]}"; do
    if [[ "$(engine_for "$i")" == "$wanted" ]]; then
      printf '%s\n' "$i"
    fi
  done
  return 0
}
validate_engine_layout(){ [[ "$(engine_for lobby)" == bds ]] || die "Lobby debe permanecer en BDS."; [[ "$(engine_for survival)" == bds ]] || die "Survival debe permanecer en BDS para proteger el mundo vanilla."; local i engine; for i in "${INSTANCES[@]}"; do engine="$(engine_for "$i")"; [[ "$engine" == bds || "$engine" == pnx ]] || die "Motor inválido para $i: $engine"; done; }
lock_manager(){ mkdir -p /run/lock; exec 9>/run/lock/bedrock-network.lock; flock -n 9 || die "Ya existe otra operación administrativa en ejecución."; }
current_bds_version(){ [[ -f "$STATE_DIR/bds-version" ]] && { cat "$STATE_DIR/bds-version"; return; }; [[ -L "$CURRENT_LINK" ]] && { basename "$(readlink -f "$CURRENT_LINK")"; return; }; printf 'none'; }
current_pnx_version(){ [[ -f "$STATE_DIR/pnx-version" ]] && { cat "$STATE_DIR/pnx-version"; return; }; [[ -L "$PNX_CURRENT_LINK" ]] && { basename "$(readlink -f "$PNX_CURRENT_LINK")"; return; }; printf 'none'; }
stop_network(){ local i; for i in "${INSTANCES[@]}"; do systemctl stop "bedrock@$i.service" 2>/dev/null || true; done; }
start_network(){ local i; for i in "${INSTANCES[@]}"; do systemctl start "bedrock@$i.service"; done; }
restart_network(){ stop_network; start_network; }
active_instances(){
  local i
  for i in "${INSTANCES[@]}"; do
    if systemctl is-active --quiet "bedrock@$i.service" 2>/dev/null; then
      printf '%s\n' "$i"
    fi
  done
  return 0
}
start_instance_list(){
  local list="$1" i
  while IFS= read -r i; do
    [[ -n "$i" ]] || continue
    systemctl start "bedrock@$i.service"
  done <<< "$list"
  # An empty previous-active list is normal on first bootstrap. Never leak the
  # false status from `[[ -n "$i" ]]` into a caller running with `set -e`.
  return 0
}
instances_healthy(){ local list="$1" i failed=0; sleep 2; while IFS= read -r i; do [[ -n "$i" ]] || continue; systemctl is-active --quiet "bedrock@$i.service" || { warn "$i no está activo."; failed=1; }; done <<< "$list"; return "$failed"; }
stop_engine(){
  local wanted="$1" i
  while IFS= read -r i; do
    [[ -n "$i" ]] || continue
    systemctl stop "bedrock@$i.service" 2>/dev/null || true
  done < <(instances_by_engine "$wanted")
  return 0
}
start_engine(){
  local wanted="$1" i
  while IFS= read -r i; do
    [[ -n "$i" ]] || continue
    systemctl start "bedrock@$i.service"
  done < <(instances_by_engine "$wanted")
  return 0
}
services_healthy(){ local i failed=0; sleep 2; for i in "${INSTANCES[@]}"; do systemctl is-active --quiet "bedrock@$i.service" || { warn "$i no está activo."; failed=1; }; done; return "$failed"; }
assert_survival_safe(){ "$APP_DIR/scripts/check-survival-safety.sh" "$INSTANCES_DIR/survival/server.properties"; }
install_units(){
  cp "$APP_DIR/systemd/bedrock@.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-backup-survival.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-backup-survival.timer" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-web.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-auto-update.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-auto-update.timer" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-survival-import.service" /etc/systemd/system/
  cp "$APP_DIR/systemd/bedrock-survival-import.path" /etc/systemd/system/
  mkdir -p "$ROOT/uploads/requests" "$STATE_DIR/web-imports"
  chown -R bedrock:bedrock "$ROOT/uploads" "$STATE_DIR/web-imports"
  chmod 0750 "$ROOT/uploads" "$ROOT/uploads/requests" "$STATE_DIR/web-imports"
  systemctl daemon-reload
  local i
  for i in "${INSTANCES[@]}"; do systemctl enable "bedrock@$i.service" >/dev/null; done
  systemctl enable bedrock-backup-survival.timer bedrock-web.service bedrock-survival-import.path >/dev/null
  systemctl start bedrock-survival-import.path >/dev/null 2>&1 || true
}
