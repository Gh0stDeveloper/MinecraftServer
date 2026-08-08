#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${BEDROCK_ROOT:-/opt/bedrock-network}"; APP_DIR="$ROOT/app"
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Ejecuta con sudo/root.' >&2; exit 1; }; }; require_root
HOST=""; WEB_PORT="8080"; BDS_VERSION="latest"; DOMAIN=""
while [[ $# -gt 0 ]]; do case "$1" in --host) HOST="${2:-}"; shift 2;; --web-port) WEB_PORT="${2:-}"; shift 2;; --bds-version) BDS_VERSION="${2:-}"; shift 2;; --domain) DOMAIN="${2:-}"; shift 2;; *) echo "Opción desconocida: $1" >&2; exit 1;; esac; done
ARCH="$(uname -m)"; [[ "$ARCH" == x86_64 || "$ARCH" == amd64 ]] || { echo "BDS Linux oficial requiere x86_64/AMD64. Detectado: $ARCH" >&2; exit 1; }
echo '[mcserver] Instalando dependencias...'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip rsync tar python3 jq git maven openjdk-21-jdk-headless ufw nginx util-linux
java -version 2>&1 | grep -Eq 'version "(21|2[2-9]|[3-9][0-9])' || { echo 'Se requiere Java 21+ para PowerNukkitX.' >&2; exit 1; }
if ! id bedrock >/dev/null 2>&1; then useradd --system --create-home --home-dir "$ROOT" --shell /usr/sbin/nologin bedrock; fi
mkdir -p "$APP_DIR" "$ROOT"/{bds/releases,pnx/releases,instances,backups,state,config,cache,addons,scripts,plugin-build}
rsync -a --delete --exclude='.git' --exclude='*.zip' --exclude='*.tar.gz' "$SOURCE_ROOT/" "$APP_DIR/"
rsync -a --delete "$APP_DIR/scripts/" "$ROOT/scripts/"; rsync -a --delete "$APP_DIR/addons/" "$ROOT/addons/"
chmod +x "$APP_DIR/mcserver" "$APP_DIR/install.sh" "$ROOT/scripts"/*.sh "$ROOT/scripts/bds-resolver.py" 2>/dev/null || true
ln -sfn "$APP_DIR/mcserver" /usr/local/bin/mcserver
if [[ -z "$HOST" ]]; then if [[ -r /dev/tty ]]; then read -r -p 'IP o dominio público de Minecraft: ' HOST </dev/tty; else echo 'Usa --host.' >&2; exit 1; fi; fi
[[ -n "$HOST" ]] || { echo 'El host no puede estar vacío.' >&2; exit 1; }
CONFIG="$ROOT/config/network.env"; [[ -f "$CONFIG" ]] || cp "$APP_DIR/config/network.env" "$CONFIG"
ENGINES="$ROOT/config/engines.env"; [[ -f "$ENGINES" ]] || cp "$APP_DIR/config/engines.env" "$ENGINES"
sed -i "s|^PUBLIC_HOST=.*|PUBLIC_HOST=$HOST|" "$CONFIG"; sed -i "s|^WEB_PORT=.*|WEB_PORT=$WEB_PORT|" "$CONFIG"
chmod 0640 "$CONFIG" "$ENGINES"; chown root:bedrock "$CONFIG" "$ENGINES"
for INSTANCE in lobby survival pvp bedwars skywars; do TARGET="$ROOT/instances/$INSTANCE"; mkdir -p "$TARGET"; [[ -f "$TARGET/server.properties" ]] || cp "$APP_DIR/instances/$INSTANCE/server.properties" "$TARGET/"; [[ -f "$TARGET/allowlist.json" ]] || cp "$APP_DIR/instances/$INSTANCE/allowlist.json" "$TARGET/"; [[ -f "$TARGET/permissions.json" ]] || cp "$APP_DIR/instances/$INSTANCE/permissions.json" "$TARGET/"; done
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
"$APP_DIR/scripts/render-lobby-config.sh"
"$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp"
"$APP_DIR/scripts/plugin-manager.sh" sync
source "$CONFIG"
for PORT in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do ufw allow "$PORT/udp" >/dev/null 2>&1 || true; done
ufw allow "$WEB_PORT/tcp" >/dev/null 2>&1 || true
systemctl enable --now bedrock-web.service; start_network
[[ -n "$DOMAIN" ]] && "$APP_DIR/scripts/web-setup.sh" domain "$DOMAIN"
"$APP_DIR/scripts/check-survival-safety.sh" "$ROOT/instances/survival/server.properties"
printf '\n[OK] Instalación híbrida terminada.\nMinecraft: %s:%s\nWeb: http://%s:%s\n\nMotores: lobby=bds survival=bds pvp=pnx bedwars=pnx skywars=pnx\nUsa: sudo mcserver update\n' "$HOST" "$LOBBY_PORT" "$HOST" "$WEB_PORT"
