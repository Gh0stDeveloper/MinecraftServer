#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"
APP_DIR="$ROOT/app"
source "$SOURCE_ROOT/scripts/ui.sh"

require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { ui_error 'Ejecuta con sudo/root.'; exit 1; }; }
require_root

HOST=""
WEB_PORT="8080"
BDS_VERSION="latest"
DOMAIN=""
PUBLIC_IP_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2;;
    --public-ip) PUBLIC_IP_OVERRIDE="${2:-}"; shift 2;;
    --web-port) WEB_PORT="${2:-}"; shift 2;;
    --bds-version) BDS_VERSION="${2:-}"; shift 2;;
    --domain) DOMAIN="${2:-}"; shift 2;;
    *) ui_error "Opción desconocida: $1"; exit 1;;
  esac
done

ui_banner "Instalación guiada · BDS + PowerNukkitX"

ARCH="$(uname -m)"
[[ "$ARCH" == x86_64 || "$ARCH" == amd64 ]] || { ui_error "BDS Linux oficial requiere x86_64/AMD64. Detectado: $ARCH"; exit 1; }

install_dependencies(){
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates curl unzip rsync tar python3 jq git maven openjdk-21-jdk-headless \
    ufw nginx util-linux iproute2 iptables >/dev/null
}
ui_section "Preparación del sistema"
ui_run_task "Instalando dependencias del servidor" install_dependencies
java -version 2>&1 | grep -Eq 'version "(21|2[2-9]|[3-9][0-9])' || { ui_error 'Se requiere Java 21+ para PowerNukkitX.'; exit 1; }
ui_ok "Arquitectura $ARCH y Java 21+ verificados"

if ! id bedrock >/dev/null 2>&1; then useradd --system --create-home --home-dir "$ROOT" --shell /usr/sbin/nologin bedrock; fi
mkdir -p "$APP_DIR" "$ROOT"/{bds/releases,pnx/releases,instances,backups,state,config,cache,addons,scripts,plugin-build,minigames,uploads}
rsync -a --delete --exclude='.git' --exclude='*.zip' --exclude='*.tar.gz' "$SOURCE_ROOT/" "$APP_DIR/"
rsync -a --delete "$APP_DIR/scripts/" "$ROOT/scripts/"
rsync -a --delete "$APP_DIR/addons/" "$ROOT/addons/"
chmod 0755 "$APP_DIR/mcserver" "$APP_DIR/install.sh" "$APP_DIR/scripts"/*.sh 2>/dev/null || true
ln -sfn "$APP_DIR/mcserver" /usr/local/bin/mcserver

CONFIG="$ROOT/config/network.env"
ENGINES="$ROOT/config/engines.env"
[[ -f "$CONFIG" ]] || cp "$APP_DIR/config/network.env" "$CONFIG"
[[ -f "$ENGINES" ]] || cp "$APP_DIR/config/engines.env" "$ENGINES"

read_env_value(){
  local file="$1" key="$2" value
  value="$(grep -m1 "^${key}=" "$file" 2>/dev/null || true)"
  value="${value#*=}"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}
valid_ipv4(){ python3 - "$1" <<'PY' >/dev/null 2>&1
import ipaddress,sys
try:
    a=ipaddress.ip_address(sys.argv[1])
    raise SystemExit(0 if a.version == 4 else 1)
except ValueError:
    raise SystemExit(1)
PY
}
detect_public_ipv4(){
  local candidate=""
  for endpoint in https://api.ipify.org https://ipv4.icanhazip.com; do
    candidate="$(curl -4fsS --max-time 7 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -n "$candidate" ]] && valid_ipv4 "$candidate"; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}
normalize_domain(){
  local d="$1"
  d="${d#http://}"; d="${d#https://}"; d="${d%%/*}"; d="${d%.}"
  printf '%s' "${d,,}"
}
valid_domain(){
  [[ -z "$1" ]] && return 1
  python3 - "$1" <<'PY' >/dev/null 2>&1
import re,sys
name=sys.argv[1]
if len(name)>253: raise SystemExit(1)
labels=name.split('.')
if len(labels)<2: raise SystemExit(1)
ok=all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', x) for x in labels)
raise SystemExit(0 if ok else 1)
PY
}
domain_matches_ip(){
  local domain="$1" expected="$2"
  [[ -n "$domain" && -n "$expected" ]] || return 1
  local -a addresses=()
  mapfile -t addresses < <(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
  [[ ${#addresses[@]} -eq 1 && "${addresses[0]}" == "$expected" ]] || return 1
  [[ -z "$(getent ahostsv6 "$domain" 2>/dev/null | awk '{print $1}' | sort -u)" ]]
}
set_env(){
  local file="$1" key="$2" value="$3" escaped
  escaped="${value//|/\\|}"
  if grep -q "^${key}=" "$file"; then sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" "$file"; else printf '%s="%s"\n' "$key" "$value" >> "$file"; fi
}

wait_bedrock_entry(){
  local instance="$1" port="$2" tries=0 probe="$APP_DIR/scripts/bedrock-ping.py"
  while (( tries < 60 )); do
    if python3 "$probe" "$port" >/dev/null 2>&1; then
      ui_ok "$instance publica un anuncio Bedrock completo en UDP/$port"
      return 0
    fi
    sleep 2
    tries=$((tries+1))
  done
  journalctl -u "bedrock@$instance.service" -n 40 --no-pager >&2 || true
  journalctl -u bedrock-gateway.service -n 40 --no-pager >&2 || true
  ui_error "$instance no quedó accesible en UDP/$port. Revisa los logs anteriores."
  return 1
}

existing_ip="$(read_env_value "$CONFIG" PUBLIC_IP)"
existing_domain="$(read_env_value "$CONFIG" PUBLIC_DOMAIN)"
PUBLIC_IP="${PUBLIC_IP_OVERRIDE:-$existing_ip}"
ui_section "Red pública"
if [[ -z "$PUBLIC_IP" ]] || ! valid_ipv4 "$PUBLIC_IP"; then
  ui_step "Detectando IPv4 pública de la VPS"
  PUBLIC_IP="$(detect_public_ipv4 || true)"
  [[ -n "$PUBLIC_IP" ]] && ui_ok "IPv4 pública detectada: $PUBLIC_IP" || ui_warn "No se pudo detectar automáticamente la IPv4 pública."
fi
if [[ -z "$PUBLIC_IP" ]] || ! valid_ipv4 "$PUBLIC_IP"; then
  if [[ -r /dev/tty ]]; then PUBLIC_IP="$(ui_prompt 'IPv4 pública de esta VPS')"; fi
fi
valid_ipv4 "$PUBLIC_IP" || { ui_error 'No se pudo obtener una IPv4 pública válida. Usa --public-ip X.X.X.X.'; exit 1; }

[[ -n "$DOMAIN" ]] || DOMAIN="$existing_domain"
if [[ -z "$DOMAIN" && -r /dev/tty ]]; then
  ui_section "Dominio del servidor"
  ui_note "Recomendado: crea gratis un subdominio en https://www.duckdns.org/"
  ui_note "Ejemplo: miservidor.duckdns.org → $PUBLIC_IP"
  DOMAIN="$(ui_prompt 'Dominio público (Enter para continuar solo con IP)')"
fi
DOMAIN="$(normalize_domain "$DOMAIN")"
if [[ -n "$DOMAIN" ]] && ! valid_domain "$DOMAIN"; then ui_error "Dominio inválido: $DOMAIN"; exit 1; fi

DNS_STATE="sin-dominio"
if [[ -n "$DOMAIN" ]]; then
  if domain_matches_ip "$DOMAIN" "$PUBLIC_IP"; then DNS_STATE="verificado"; else DNS_STATE="pendiente"; fi
fi
if [[ -z "$HOST" ]]; then HOST="$PUBLIC_IP"; fi
[[ -n "$HOST" ]] || { ui_error 'El host público no puede estar vacío.'; exit 1; }
if [[ -n "$DOMAIN" && "$HOST" == "$DOMAIN" ]]; then
  TRANSFER_HOST_MODE=domain
elif [[ "$HOST" == "$PUBLIC_IP" ]]; then
  TRANSFER_HOST_MODE=ip
else
  TRANSFER_HOST_MODE=custom
fi

set_env "$CONFIG" PUBLIC_IP "$PUBLIC_IP"
set_env "$CONFIG" PUBLIC_DOMAIN "$DOMAIN"
set_env "$CONFIG" PUBLIC_HOST "$HOST"
set_env "$CONFIG" TRANSFER_HOST_MODE "$TRANSFER_HOST_MODE"
set_env "$CONFIG" WEB_PORT "$WEB_PORT"
chmod 0640 "$CONFIG" "$ENGINES"; chown root:bedrock "$CONFIG" "$ENGINES"

ui_section "Configuración detectada"
ui_kv "IPv4 pública" "$PUBLIC_IP"
ui_kv "Dominio" "${DOMAIN:-no configurado}"
ui_kv "Host activo" "$HOST"
ui_kv "Transferencias" "$TRANSFER_HOST_MODE"
if [[ -n "$DOMAIN" && "$DNS_STATE" == pendiente ]]; then
  ui_warn "$DOMAIN todavía no apunta a $PUBLIC_IP; se usará la IP temporalmente."
  ui_note "Cuando actualices DuckDNS/DNS: sudo mcserver network use-domain"
fi

for INSTANCE in lobby survival pvp bedwars skywars; do
  TARGET="$ROOT/instances/$INSTANCE"; mkdir -p "$TARGET"
  [[ -f "$TARGET/server.properties" ]] || cp "$APP_DIR/instances/$INSTANCE/server.properties" "$TARGET/"
  [[ -f "$TARGET/allowlist.json" ]] || cp "$APP_DIR/instances/$INSTANCE/allowlist.json" "$TARGET/"
  [[ -f "$TARGET/permissions.json" ]] || cp "$APP_DIR/instances/$INSTANCE/permissions.json" "$TARGET/"
done

chown -R bedrock:bedrock "$ROOT"
chown root:bedrock "$CONFIG" "$ENGINES"
if [[ ! -f "$ROOT/instances/survival/worlds/SurvivalWorld/level.dat" ]]; then
  touch "$ROOT/state/survival-pending-import"
  chown bedrock:bedrock "$ROOT/state/survival-pending-import"
fi
bash "$APP_DIR/scripts/normalize-permissions.sh" >/dev/null

source "$APP_DIR/scripts/lib.sh"
source_config
source_engines
ui_section "Runtimes y servicios"
ui_run_task "Instalando unidades systemd" bash -c 'source "$1"; install_units' _ "$APP_DIR/scripts/lib.sh"
ui_run_task "Configurando gateway y backends BDS" bash "$APP_DIR/scripts/configure-instances.sh"
ui_run_task "Instalando/actualizando Bedrock Dedicated Server" bash "$APP_DIR/scripts/update-bds.sh" "$BDS_VERSION"
bash "$APP_DIR/scripts/update-pnx.sh" latest
ui_run_task "Preparando instancias PowerNukkitX" bash "$APP_DIR/scripts/engine-manager.sh" prepare

ui_section "Lobby y minijuegos"
systemctl start bedrock@lobby.service
LEVEL="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$ROOT/instances/lobby/server.properties")"
TRY=0
while [[ ! -d "$ROOT/instances/lobby/worlds/$LEVEL" && $TRY -lt 30 ]]; do sleep 1; TRY=$((TRY+1)); done
systemctl stop bedrock@lobby.service || true
[[ -d "$ROOT/instances/lobby/worlds/$LEVEL" ]] || { ui_error "No se creó el mundo del lobby: $LEVEL"; exit 1; }
ui_run_task "Instalando plugins Nexora" bash "$APP_DIR/scripts/plugin-manager.sh" sync
ui_run_task "Preparando PvP, BedWars y SkyWars" bash "$APP_DIR/scripts/minigame-manager.sh" prepare
ui_run_task "Actualizando configuración del Lobby" bash "$APP_DIR/scripts/render-lobby-config.sh"
ui_run_task "Instalando addon del Lobby" bash "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp"
ui_run_task "Aplicando firewall local" bash "$APP_DIR/scripts/firewall-manager.sh" apply

systemctl enable --now bedrock-web.service bedrock-gateway.service >/dev/null 2>&1
for instance in lobby pvp bedwars skywars; do systemctl restart "bedrock@$instance.service"; done
if [[ -f "$ROOT/state/survival-pending-import" ]]; then systemctl stop bedrock@survival.service 2>/dev/null || true; else systemctl restart bedrock@survival.service; fi

ui_section "Validación de entradas Bedrock"
wait_bedrock_entry lobby "$LOBBY_PORT"
wait_bedrock_entry pvp "$PVP_PORT"
wait_bedrock_entry bedwars "$BEDWARS_PORT"
wait_bedrock_entry skywars "$SKYWARS_PORT"
if [[ ! -f "$ROOT/state/survival-pending-import" ]]; then wait_bedrock_entry survival "$SURVIVAL_PORT"; fi

if [[ ! -s "$ROOT/config/web-admin.token.sha256" ]]; then
  ui_section "Panel administrativo"
  bash "$APP_DIR/scripts/web-setup.sh" admin-token
fi
if [[ -n "$DOMAIN" && "$DNS_STATE" == verificado ]]; then ui_run_task "Configurando Nginx para $DOMAIN" bash "$APP_DIR/scripts/web-setup.sh" domain "$DOMAIN"; fi
bash "$APP_DIR/scripts/check-survival-safety.sh" "$ROOT/instances/survival/server.properties" >/dev/null

ui_section "Instalación completada"
ui_ok "Nexora Network está preparada"
ui_kv "Minecraft" "$HOST:$LOBBY_PORT"
ui_kv "BDS" "$(current_bds_version)"
ui_kv "PowerNukkitX" "$(current_pnx_version)"
ui_kv "Web interna" "http://127.0.0.1:$WEB_PORT"
ui_kv "Survival" "pendiente de importar (protegido)"
if [[ -n "$DOMAIN" ]]; then ui_kv "Panel" "https://$DOMAIN/admin.html (requiere HTTPS)"; else ui_note "Añade un dominio después con: sudo mcserver web domain TU_DOMINIO"; fi
ui_note "Siguiente comprobación: sudo mcserver doctor"
ui_note "Logs detallados de tareas: $(ui_log_dir)/tasks.log"
