#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/socket-check.sh"
require_root
source_config
source_engines
validate_engine_layout

ensure_dependencies(){
  local missing=0 cmd
  for cmd in curl unzip rsync python3 jq git mvn java ss iptables; do command -v "$cmd" >/dev/null 2>&1 || missing=1; done
  if ((missing)); then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl unzip rsync tar python3 jq git maven openjdk-21-jdk-headless iproute2 iptables >/dev/null
  fi
}

set_server_property(){
  local file="$1" key="$2" value="$3"
  [[ -f "$file" ]] || return 0
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

ensure_bds_raknet(){
  local file

  file="$INSTANCES_DIR/lobby/server.properties"
  if [[ -f "$file" ]]; then
    set_server_property "$file" transport raknet
    # El Lobby usa el puerto Bedrock estándar 19132 y debe devolver el anuncio
    # MCPE del Unconnected Pong. Desactivar esta opción deja un pong RakNet
    # desnudo en BDS recientes y hace que el servidor aparezca como no disponible.
    set_server_property "$file" enable-lan-visibility true
  fi

  file="$INSTANCES_DIR/survival/server.properties"
  if [[ -f "$file" ]]; then
    set_server_property "$file" transport raknet
    # Survival usa un puerto no estándar. Aquí sí desactivamos el listener LAN
    # adicional para que BDS no intente enlazar también 19132/19133.
    set_server_property "$file" enable-lan-visibility false
  fi
}

wait_udp(){
  local instance="$1" port="$2" tries=0 state
  while ((tries < 45)); do
    if udp_port_listening "$port"; then ok "$instance escuchando en UDP/$port"; return 0; fi
    state="$(systemctl is-active "bedrock@$instance.service" 2>/dev/null || true)"
    if [[ "$state" == failed ]]; then journalctl -u "bedrock@$instance.service" -n 40 --no-pager >&2 || true; die "$instance falló durante el arranque."; fi
    sleep 2; tries=$((tries+1))
  done
  journalctl -u "bedrock@$instance.service" -n 40 --no-pager >&2 || true
  die "$instance no abrió UDP/$port dentro del tiempo de validación."
}

prepare_lobby_world(){
  local level tries=0
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/lobby/server.properties" 2>/dev/null || true)"
  [[ -n "$level" ]] || die "Lobby no tiene level-name configurado."
  if [[ ! -d "$INSTANCES_DIR/lobby/worlds/$level" ]]; then
    ui_step "Generando por primera vez el mundo del Lobby"
    systemctl start bedrock@lobby.service
    while [[ ! -d "$INSTANCES_DIR/lobby/worlds/$level" && $tries -lt 30 ]]; do
      systemctl is-failed --quiet bedrock@lobby.service && { journalctl -u bedrock@lobby.service -n 40 --no-pager >&2 || true; die "Lobby falló antes de crear el mundo."; }
      sleep 1; tries=$((tries+1))
    done
    systemctl stop bedrock@lobby.service || true
  fi
  [[ -d "$INSTANCES_DIR/lobby/worlds/$level" ]] || die "No se pudo crear el mundo del lobby: $level"
  ui_run_task "Instalando addon del Lobby" bash "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp"
}

start_runtime_services(){
  systemctl enable --now bedrock-web.service >/dev/null 2>&1
  local instance
  for instance in lobby pvp bedwars skywars; do systemctl restart "bedrock@$instance.service"; done
  if [[ -f "$STATE_DIR/survival-pending-import" ]]; then systemctl stop bedrock@survival.service 2>/dev/null || true; else systemctl restart bedrock@survival.service; fi
}

ui_banner "Recuperación y bootstrap del servidor"
ui_section "Base del sistema"
ui_run_task "Verificando dependencias" ensure_dependencies
ui_run_task "Normalizando permisos" bash "$APP_DIR/scripts/normalize-permissions.sh"
ui_run_task "Instalando unidades systemd" bash -c 'source "$1"; install_units' _ "$APP_DIR/scripts/lib.sh"
ui_run_task "Aplicando firewall local" bash "$APP_DIR/scripts/firewall-manager.sh" apply

ui_section "Runtimes"
bash "$APP_DIR/scripts/update-bds.sh" latest
ui_run_task "Forzando transporte RakNet en BDS" ensure_bds_raknet
bash "$APP_DIR/scripts/update-pnx.sh" latest
ui_run_task "Preparando instancias PowerNukkitX" bash "$APP_DIR/scripts/engine-manager.sh" prepare

ui_section "Lobby y minijuegos"
prepare_lobby_world
ui_run_task "Sincronizando plugins Nexora" bash "$APP_DIR/scripts/plugin-manager.sh" sync
ui_run_task "Preparando PvP, BedWars y SkyWars" bash "$APP_DIR/scripts/minigame-manager.sh" prepare
ui_run_task "Renderizando configuración del Lobby" bash "$APP_DIR/scripts/render-lobby-config.sh"

ui_section "Arranque"
ui_run_task "Iniciando Lobby, minijuegos y web" start_runtime_services
if [[ -f "$STATE_DIR/survival-pending-import" ]]; then ui_note "Survival permanece detenido hasta importar el mundo desde el panel web o mcserver import-survival."; fi
wait_udp lobby "$LOBBY_PORT"
wait_udp pvp "$PVP_PORT"
wait_udp bedwars "$BEDWARS_PORT"
wait_udp skywars "$SKYWARS_PORT"

ui_section "Validación final"
ui_run_task "Validando plugins" bash "$APP_DIR/scripts/plugin-manager.sh" doctor
ui_run_task "Validando minijuegos" bash "$APP_DIR/scripts/minigame-manager.sh" verify
ui_run_task "Protegiendo logros de Survival" bash "$APP_DIR/scripts/check-survival-safety.sh" "$INSTANCES_DIR/survival/server.properties"
ui_run_task "Validando red local" bash "$APP_DIR/scripts/network-manager.sh" verify

ui_section "Listo"
ok "Bootstrap terminado: runtimes, plugins, minijuegos, web y firewall local listos."
ui_kv "BDS" "$(current_bds_version)"
ui_kv "PowerNukkitX" "$(current_pnx_version)"
ui_kv "Servidor" "$PUBLIC_HOST:$LOBBY_PORT"
ui_kv "Survival" "$([[ -f "$STATE_DIR/survival-pending-import" ]] && printf 'pendiente de importar' || printf 'activo')"
ui_note "Log técnico: $(ui_log_dir)/tasks.log"
