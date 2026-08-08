#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"; APP_DIR="$ROOT/app"
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Ejecuta con sudo/root.' >&2; exit 1; }; }; require_root
HOST=""; WEB_PORT="8080"; BDS_VERSION="latest"; DOMAIN=""; PUBLIC_IP_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2;;
    --public-ip) PUBLIC_IP_OVERRIDE="${2:-}"; shift 2;;
    --web-port) WEB_PORT="${2:-}"; shift 2;;
    --bds-version) BDS_VERSION="${2:-}"; shift 2;;
    --domain) DOMAIN="${2:-}"; shift 2;;
    *) echo "Opción desconocida: $1" >&2; exit 1;;
  esac
done
ARCH="$(uname -m)"; [[ "$ARCH" == x86_64 || "$ARCH" == amd64 ]] || { echo "BDS Linux oficial requiere x86_64/AMD64. Detectado: $ARCH" >&2; exit 1; }
echo '[mcserver] Instalando dependencias...'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip rsync tar python3 jq git maven openjdk-21-jdk-headless ufw nginx util-linux iproute2
java -version 2>&1 | grep -Eq 'version "(21|2[2-9]|[3-9][0-9])' || { echo 'Se requiere Java 21+ para PowerNukkitX.' >&2; exit 1; }
if ! id bedrock >/dev/null 2>&1; then useradd --system --create-home --home-dir "$ROOT" --shell /usr/sbin/nologin bedrock; fi
mkdir -p "$APP_DIR" "$ROOT"/{bds/releases,pnx/releases,instances,backups,state,config,cache,addons,scripts,plugin-build,minigames}
rsync -a --delete --exclude='.git' --exclude='*.zip' --exclude='*.tar.gz' "$SOURCE_ROOT/" "$APP_DIR/"
rsync -a --delete "$APP_DIR/scripts/" "$ROOT/scripts/"; rsync -a --delete "$APP_DIR/addons/" "$ROOT/addons/"
chmod +x "$APP_DIR/mcserver" "$APP_DIR/install.sh" "$ROOT/scripts"/*.sh "$ROOT/scripts/bds-resolver.py" 2>/dev/null || true
ln -sfn "$APP_DIR/mcserver" /usr/local/bin/mcserver

TEMPLATE_IP="$(awk -F= '$1=="PUBLIC_IP"{gsub(/[\"[:space:]]/,"",$2); print $2; exit}' "$APP_DIR/config/network.env" 2>/dev/null || true)"
TEMPLATE_DOMAIN="$(awk -F= '$1=="PUBLIC_DOMAIN"{gsub(/[\"[:space:]]/,"",$2); print $2; exit}' "$APP_DIR/config/network.env" 2>/dev/null || true)"
PUBLIC_IP="${PUBLIC_IP_OVERRIDE:-$TEMPLATE_IP}"
[[ -n "$DOMAIN" ]] || DOMAIN="$TEMPLATE_DOMAIN"

domain_matches_ip(){
  local domain="$1" expected="$2"
  [[ -n "$domain" && -n "$expected" ]] || return 1
  getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | grep -Fxq "$expected"
}

if [[ -z "$HOST" ]]; then
  if domain_matches_ip "$DOMAIN" "$PUBLIC_IP"; then
    HOST="$DOMAIN"
    echo "[mcserver] DNS verificado: $DOMAIN -> $PUBLIC_IP"
  elif [[ -n "$PUBLIC_IP" ]]; then
    HOST="$PUBLIC_IP"
    [[ -n "$DOMAIN" ]] && echo "[mcserver] DNS aún no apunta a $PUBLIC_IP; se usará la IP como fallback."
  elif [[ -r /dev/tty ]]; then
    read -r -p 'IP o dominio público de Minecraft: ' HOST </dev/tty
  else
    echo 'Usa --host o configura PUBLIC_IP/PUBLIC_DOMAIN.' >&2; exit 1
  fi
fi
[[ -n "$HOST" ]] || { echo 'El host no puede estar vacío.' >&2; exit 1; }

CONFIG="$ROOT/config/network.env"; [[ -f "$CONFIG" ]] || cp "$APP_DIR/config/network.env" "$CONFIG"
ENGINES="$ROOT/config/engines.env"; [[ -f "$ENGINES" ]] || cp "$APP_DIR/config/engines.env" "$ENGINES"
if grep -q '^PUBLIC_IP=' "$CONFIG"; then sed -i "s|^PUBLIC_IP=.*|PUBLIC_IP=$PUBLIC_IP|" "$CONFIG"; else printf '\nPUBLIC_IP=%s\n' "$PUBLIC_IP" >> "$CONFIG"; fi
if grep -q '^PUBLIC_DOMAIN=' "$CONFIG"; then sed -i "s|^PUBLIC_DOMAIN=.*|PUBLIC_DOMAIN=$DOMAIN|" "$CONFIG"; else printf 'PUBLIC_DOMAIN=%s\n' "$DOMAIN" >> "$CONFIG"; fi
sed -i "s|^PUBLIC_HOST=.*|PUBLIC_HOST=$HOST|" "$CONFIG"; sed -i "s|^WEB_PORT=.*|WEB_PORT=$WEB_PORT|" "$CONFIG"
chmod 0640 "$CONFIG" "$ENGINES"; chown root:bedrock "$CONFIG" "$ENGINES"
for INSTANCE in lobby survival pvp bedwars skywars; do
  TARGET="$ROOT/instances/$INSTANCE"; mkdir -p "$TARGET"
  [[ -f "$TARGET/server.properties" ]] || cp "$APP_DIR/instances/$INSTANCE/server.properties" "$TARGET/"
  [[ -f "$TARGET/allowlist.json" ]] || cp "$APP_DIR/instances/$INSTANCE/allowlist.json" "$TARGET/"
  [[ -f "$TARGET/permissions.json" ]] || cp "$APP_DIR/instances/$INSTANCE/permissions.json" "$TARGET/"
done
chown -R bedrock:bedrock "$ROOT"; chown root:bedrock "$CONFIG" "$ENGINES"
if [[ ! -f "$ROOT/instances/survival/worlds/SurvivalWorld/level.dat" ]]; then touch "$ROOT/state/survival-pending-import"; chown bedrock:bedrock "$ROOT/state/survival-pending-import"; fi
source "$APP_DIR/scripts/lib.sh"; install_units
"$APP_DIR/scripts/update-bds.sh" "$BDS_VERSION"
"$APP_DIR/scripts/update-pnx.sh" latest
"$APP_DIR/scripts/engine-manager.sh" prepare

# Crear únicamente el mundo BDS del lobby; Survival se importa aparte.
systemctl start bedrock@lobby.service
LEVEL="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$ROOT/instances/lobby/server.properties")"
TRY=0; while [[ ! -d "$ROOT/instances/lobby/worlds/$LEVEL" && $TRY -lt 30 ]]; do sleep 1; TRY=$((TRY+1)); done
systemctl stop bedrock@lobby.service || true
[[ -d "$ROOT/instances/lobby/worlds/$LEVEL" ]] || { echo "No se creó el mundo del lobby: $LEVEL" >&2; exit 1; }

# Instalar plugins primero y calcular la disponibilidad real de cada modalidad después.
"$APP_DIR/scripts/plugin-manager.sh" sync
"$APP_DIR/scripts/minigame-manager.sh" prepare
"$APP_DIR/scripts/render-lobby-config.sh"
"$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp"

source "$CONFIG"
for PORT in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do ufw allow "$PORT/udp" >/dev/null 2>&1 || true; done
ufw allow "$WEB_PORT/tcp" >/dev/null 2>&1 || true
systemctl enable --now bedrock-web.service; start_network
[[ -n "$DOMAIN" ]] && "$APP_DIR/scripts/web-setup.sh" domain "$DOMAIN"
"$APP_DIR/scripts/check-survival-safety.sh" "$ROOT/instances/survival/server.properties"

DNS_STATE="sin dominio"
if [[ -n "$DOMAIN" ]]; then
  if domain_matches_ip "$DOMAIN" "$PUBLIC_IP"; then DNS_STATE="$DOMAIN -> $PUBLIC_IP (OK)"; else DNS_STATE="$DOMAIN todavía no resuelve a $PUBLIC_IP"; fi
fi
printf '\n[OK] Instalación híbrida terminada.\nMinecraft: %s:%s\nIP pública: %s\nDNS: %s\nWeb: http://%s:%s\n\nMotores: lobby=bds survival=bds pvp=pnx bedwars=pnx skywars=pnx\nPvP y BedWars quedan disponibles automáticamente con NexoraPractice/NexoraBedWars. SkyWars se habilita al importar al menos un mapa válido.\nUsa: sudo mcserver minigames status\nUsa: sudo mcserver network verify\n' "$HOST" "$LOBBY_PORT" "$PUBLIC_IP" "$DNS_STATE" "$HOST" "$WEB_PORT"
