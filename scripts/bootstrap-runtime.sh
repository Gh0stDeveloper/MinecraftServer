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

wait_udp(){
  local instance="$1" port="$2" runtime_port="${3:-$2}" tries=0 state probe="$APP_DIR/scripts/bedrock-ping.py"
  while ((tries < 60)); do
    # Lobby/Survival only receive a public MCPE pong after the gateway has
    # queried the corresponding BDS backend and received its RakNet GUID. That
    # end-to-end response is a stronger health signal than whether `ss` happens
    # to enumerate the internal BDS socket on this kernel/BDS build.
    if udp_port_listening "$port" && python3 "$probe" "$port" >/dev/null 2>&1; then
      ok "$instance operativo en UDP/$port (anuncio MCPE completo)"
      return 0
    fi
    state="$(systemctl is-active "bedrock@$instance.service" 2>/dev/null || true)"
    if [[ "$state" == failed || ( "$state" == inactive && $tries -ge 3 ) ]]; then
      journalctl -u "bedrock@$instance.service" -n 40 --no-pager >&2 || true
      die "$instance dejó de ejecutarse durante el arranque (estado=$state)."
    fi
    sleep 2; tries=$((tries+1))
  done
  if [[ "$runtime_port" != "$port" ]] && ! udp_port_listening "$runtime_port"; then
    warn "Backend UDP/$runtime_port no aparece en ss ($instance; servicio=$state)."
  fi
  journalctl -u "bedrock@$instance.service" -n 40 --no-pager >&2 || true
  journalctl -u bedrock-gateway.service -n 40 --no-pager >&2 || true
  die "$instance no publicó un anuncio Bedrock completo en UDP/$port dentro del tiempo de validación."
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
  systemctl enable --now bedrock-web.service bedrock-gateway.service >/dev/null 2>&1
  systemctl restart bedrock-gateway.service
  local instance
  for instance in lobby pvp bedwars skywars; do systemctl restart "bedrock@$instance.service"; done
  if [[ -f "$STATE_DIR/survival-pending-import" ]]; then systemctl stop bedrock@survival.service 2>/dev/null || true; else systemctl restart bedrock@survival.service; fi
}

ui_banner "Recuperación y bootstrap del servidor"
ui_section "Base del sistema"
ui_run_task "Verificando dependencias" ensure_dependencies
ui_run_task "Normalizando permisos" bash "$APP_DIR/scripts/normalize-permissions.sh"
ui_run_task "Instalando unidades systemd" bash -c 'source "$1"; install_units' _ "$APP_DIR/scripts/lib.sh"
ui_run_task "Deteniendo servicios para migrar puertos sin colisiones" stop_network
ui_run_task "Aplicando firewall local" bash "$APP_DIR/scripts/firewall-manager.sh" apply

ui_section "Runtimes"
bash "$APP_DIR/scripts/update-bds.sh" latest
ui_run_task "Configurando gateway y backends BDS" bash "$APP_DIR/scripts/configure-instances.sh"
ui_run_task "Validando host de transferencias" bash "$APP_DIR/scripts/network-manager.sh" ensure-host
bash "$APP_DIR/scripts/update-pnx.sh" latest
ui_run_task "Preparando instancias PowerNukkitX" bash "$APP_DIR/scripts/engine-manager.sh" prepare

ui_section "Lobby y minijuegos"
prepare_lobby_world
ui_run_task "Sincronizando plugins Nexora" bash "$APP_DIR/scripts/plugin-manager.sh" sync
ui_run_task "Preparando PvP, BedWars y SkyWars" bash "$APP_DIR/scripts/minigame-manager.sh" prepare
ui_run_task "Renderizando configuración del Lobby" bash "$APP_DIR/scripts/render-lobby-config.sh"
ui_run_task "Desplegando configuración actualizada del Lobby" bash "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp"

ui_section "Arranque"
ui_run_task "Iniciando Lobby, minijuegos y web" start_runtime_services
if [[ -f "$STATE_DIR/survival-pending-import" ]]; then ui_note "Survival permanece detenido hasta importar el mundo desde el panel web o mcserver import-survival."; fi
wait_udp lobby "$LOBBY_PORT" "$LOBBY_BACKEND_PORT"
wait_udp pvp "$PVP_PORT"
wait_udp bedwars "$BEDWARS_PORT"
wait_udp skywars "$SKYWARS_PORT"
if [[ ! -f "$STATE_DIR/survival-pending-import" ]]; then wait_udp survival "$SURVIVAL_PORT" "$SURVIVAL_BACKEND_PORT"; fi

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
