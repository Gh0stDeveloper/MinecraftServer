#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"
APP_DIR="$ROOT/app"
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Ejecuta con sudo/root.' >&2; exit 1; }; }
require_root
HOST=""; WEB_PORT="8080"; BDS_VERSION="latest"; DOMAIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2;;
    --web-port) WEB_PORT="${2:-}"; shift 2;;
    --bds-version) BDS_VERSION="${2:-}"; shift 2;;
    --domain) DOMAIN="${2:-}"; shift 2;;
    *) echo "Opción desconocida: $1" >&2; exit 1;;
  esac
done

ARCH="$(uname -m)"
[[ "$ARCH" == x86_64 || "$ARCH" == amd64 ]] || { echo "BDS Linux oficial requiere x86_64/AMD64. Detectado: $ARCH" >&2; exit 1; }
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" == ubuntu ]] && [[ "$(printf '%s\n%s\n' 22.04 "${VERSION_ID:-0}" | sort -V | head -n1)" != 22.04 ]]; then
    echo "Se requiere Ubuntu 22.04 LTS o posterior." >&2; exit 1
  fi
fi

echo '[mcserver] Instalando dependencias...'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip rsync tar python3 ufw nginx util-linux
if ! id bedrock >/dev/null 2>&1; then useradd --system --create-home --home-dir "$ROOT" --shell /usr/sbin/nologin bedrock; fi
mkdir -p "$APP_DIR" "$ROOT"/{bds/releases,instances,backups,state,config,cache,addons,scripts}
rsync -a --delete --exclude='.git' --exclude='*.zip' --exclude='*.tar.gz' "$SOURCE_ROOT/" "$APP_DIR/"
rsync -a --delete "$APP_DIR/scripts/" "$ROOT/scripts/"
rsync -a --delete "$APP_DIR/addons/" "$ROOT/addons/"
chmod +x "$APP_DIR/mcserver" "$APP_DIR/install.sh" "$ROOT/scripts"/*.sh "$ROOT/scripts/bds-resolver.py" 2>/dev/null || true
ln -sfn "$APP_DIR/mcserver" /usr/local/bin/mcserver

if [[ -z "$HOST" ]]; then
  if [[ -r /dev/tty ]]; then
    read -r -p 'IP o dominio público de Minecraft: ' HOST </dev/tty
  else
    echo 'Usa --host en instalación no interactiva.' >&2; exit 1
  fi
fi
[[ -n "$HOST" ]] || { echo 'El host no puede estar vacío.' >&2; exit 1; }

CONFIG="$ROOT/config/network.env"
[[ -f "$CONFIG" ]] || cp "$APP_DIR/config/network.env" "$CONFIG"
grep -q '^SERVER_NAME=' "$CONFIG" || printf '\nSERVER_NAME="Bedrock Network"\n' >> "$CONFIG"
grep -q '^WEB_PORT=' "$CONFIG" || printf 'WEB_PORT=8080\n' >> "$CONFIG"
sed -i "s|^PUBLIC_HOST=.*|PUBLIC_HOST=$HOST|" "$CONFIG"
sed -i "s|^WEB_PORT=.*|WEB_PORT=$WEB_PORT|" "$CONFIG"
sed -i 's|^BASE_DIR=.*|BASE_DIR=/opt/bedrock-network|' "$CONFIG"
sed -i 's|^BACKUP_DIR=.*|BACKUP_DIR=/opt/bedrock-network/backups|' "$CONFIG"
chmod 0640 "$CONFIG"; chown root:bedrock "$CONFIG"

for INSTANCE in lobby survival pvp bedwars skywars; do
  TARGET="$ROOT/instances/$INSTANCE"; mkdir -p "$TARGET"
  [[ -f "$TARGET/server.properties" ]] || cp "$APP_DIR/instances/$INSTANCE/server.properties" "$TARGET/"
  [[ -f "$TARGET/allowlist.json" ]] || cp "$APP_DIR/instances/$INSTANCE/allowlist.json" "$TARGET/"
  [[ -f "$TARGET/permissions.json" ]] || cp "$APP_DIR/instances/$INSTANCE/permissions.json" "$TARGET/"
done
chown -R bedrock:bedrock "$ROOT"
chown root:bedrock "$CONFIG"

# shellcheck source=lib.sh
source "$APP_DIR/scripts/lib.sh"
install_units
"$APP_DIR/scripts/update-bds.sh" "$BDS_VERSION"

# Primera ejecución para crear mundos y poder registrar addons.
for INSTANCE in lobby pvp bedwars skywars; do systemctl start "bedrock@$INSTANCE.service"; done
for INSTANCE in lobby pvp bedwars skywars; do
  LEVEL="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$ROOT/instances/$INSTANCE/server.properties")"
  TRY=0; while [[ ! -d "$ROOT/instances/$INSTANCE/worlds/$LEVEL" && $TRY -lt 30 ]]; do sleep 1; TRY=$((TRY+1)); done
done
for INSTANCE in lobby pvp bedwars skywars; do systemctl stop "bedrock@$INSTANCE.service" || true; done
"$APP_DIR/scripts/render-lobby-config.sh"
for INSTANCE in lobby pvp bedwars skywars; do
  "$APP_DIR/scripts/install-addon.sh" "$INSTANCE" "$ROOT/addons/${INSTANCE}_bp" || echo "[WARN] Addon $INSTANCE pendiente de reintento."
done

# shellcheck disable=SC1090
source "$CONFIG"
for PORT in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do ufw allow "$PORT/udp" >/dev/null 2>&1 || true; done
ufw allow "$WEB_PORT/tcp" >/dev/null 2>&1 || true
systemctl enable --now bedrock-web.service
start_network

if [[ -n "$DOMAIN" ]]; then "$APP_DIR/scripts/web-setup.sh" domain "$DOMAIN"; fi
"$APP_DIR/scripts/check-survival-safety.sh" "$ROOT/instances/survival/server.properties"
printf '\n[OK] Instalación terminada.\nMinecraft: %s:%s\nWeb: http://%s:%s\n\nUsa: sudo mcserver update\n' "$HOST" "$LOBBY_PORT" "$HOST" "$WEB_PORT"
