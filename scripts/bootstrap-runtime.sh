#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
source_engines
validate_engine_layout

ensure_dependencies(){
  local missing=0 cmd
  for cmd in curl unzip rsync python3 jq git mvn java ss iptables; do
    command -v "$cmd" >/dev/null 2>&1 || missing=1
  done
  if ((missing)); then
    log "Instalando dependencias faltantes para recuperar la red..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip rsync tar python3 jq git maven openjdk-21-jdk-headless iproute2 iptables
  fi
}

wait_udp(){
  local instance="$1" port="$2" tries=0 state
  while ((tries < 45)); do
    if ss -H -lun 2>/dev/null | awk '{print $5}' | grep -Eq "(:|\\])${port}$"; then
      ok "$instance escuchando en UDP/$port"
      return 0
    fi
    state="$(systemctl is-active "bedrock@$instance.service" 2>/dev/null || true)"
    if [[ "$state" == failed ]]; then
      journalctl -u "bedrock@$instance.service" -n 40 --no-pager >&2 || true
      die "$instance falló durante el arranque."
    fi
    sleep 2
    tries=$((tries+1))
  done
  journalctl -u "bedrock@$instance.service" -n 40 --no-pager >&2 || true
  die "$instance no abrió UDP/$port dentro del tiempo de validación."
}

prepare_lobby_world(){
  local level tries=0
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/lobby/server.properties" 2>/dev/null || true)"
  [[ -n "$level" ]] || die "Lobby no tiene level-name configurado."
  if [[ ! -d "$INSTANCES_DIR/lobby/worlds/$level" ]]; then
    log "Generando por primera vez el mundo del lobby..."
    systemctl start bedrock@lobby.service
    while [[ ! -d "$INSTANCES_DIR/lobby/worlds/$level" && $tries -lt 30 ]]; do
      systemctl is-failed --quiet bedrock@lobby.service && {
        journalctl -u bedrock@lobby.service -n 40 --no-pager >&2 || true
        die "Lobby falló antes de crear el mundo."
      }
      sleep 1
      tries=$((tries+1))
    done
    systemctl stop bedrock@lobby.service || true
  fi
  [[ -d "$INSTANCES_DIR/lobby/worlds/$level" ]] || die "No se pudo crear el mundo del lobby: $level"
  bash "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp"
}

log "Recuperando/terminando instalación de Bedrock Network..."
ensure_dependencies
bash "$APP_DIR/scripts/normalize-permissions.sh"
install_units
bash "$APP_DIR/scripts/firewall-manager.sh" apply

# Los updaters preservan el estado previo de servicios. En una instalación
# incompleta suelen estar todos apagados; el bootstrap los arranca al final.
bash "$APP_DIR/scripts/update-bds.sh" latest
bash "$APP_DIR/scripts/update-pnx.sh" latest
bash "$APP_DIR/scripts/engine-manager.sh" prepare
prepare_lobby_world
bash "$APP_DIR/scripts/plugin-manager.sh" sync
bash "$APP_DIR/scripts/minigame-manager.sh" prepare
bash "$APP_DIR/scripts/render-lobby-config.sh"

systemctl enable --now bedrock-web.service
for instance in lobby pvp bedwars skywars; do
  systemctl restart "bedrock@$instance.service"
done
if [[ -f "$STATE_DIR/survival-pending-import" ]]; then
  systemctl stop bedrock@survival.service 2>/dev/null || true
  log "Survival permanece detenido hasta importar el mundo desde el panel web o mcserver import-survival."
else
  systemctl restart bedrock@survival.service
fi

wait_udp lobby "$LOBBY_PORT"
wait_udp pvp "$PVP_PORT"
wait_udp bedwars "$BEDWARS_PORT"
wait_udp skywars "$SKYWARS_PORT"

bash "$APP_DIR/scripts/plugin-manager.sh" doctor
bash "$APP_DIR/scripts/minigame-manager.sh" verify
bash "$APP_DIR/scripts/check-survival-safety.sh" "$INSTANCES_DIR/survival/server.properties"
bash "$APP_DIR/scripts/network-manager.sh" verify

ok "Bootstrap terminado: runtimes, plugins, minijuegos, web y firewall local listos."
