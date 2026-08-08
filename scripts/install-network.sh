#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Usa sudo." >&2; exit 1; fi
if [[ $# -ne 1 ]]; then echo "Uso: $0 /ruta/bedrock-server-linux.zip" >&2; exit 1; fi
ZIP="$(realpath "$1")"
[[ -f "$ZIP" ]] || { echo "No existe: $ZIP" >&2; exit 1; }

SRC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/opt/bedrock-network

mkdir -p "$DEST"/{instances,backups,scripts,addons,config}
cp -a "$SRC_ROOT/scripts/." "$DEST/scripts/"
cp -a "$SRC_ROOT/addons/." "$DEST/addons/"
cp -a "$SRC_ROOT/config/." "$DEST/config/"

for INSTANCE in lobby survival pvp bedwars skywars; do
  TARGET="$DEST/instances/$INSTANCE"
  mkdir -p "$TARGET"
  unzip -q -o "$ZIP" -d "$TARGET"
  cp "$SRC_ROOT/instances/$INSTANCE/server.properties" "$TARGET/server.properties"
  cp "$SRC_ROOT/instances/$INSTANCE/allowlist.json" "$TARGET/allowlist.json"
  cp "$SRC_ROOT/instances/$INSTANCE/permissions.json" "$TARGET/permissions.json"
  chmod +x "$TARGET/bedrock_server"
done

cp "$SRC_ROOT/systemd/bedrock@.service" /etc/systemd/system/bedrock@.service
cp "$SRC_ROOT/systemd/bedrock-backup-survival.service" /etc/systemd/system/
cp "$SRC_ROOT/systemd/bedrock-backup-survival.timer" /etc/systemd/system/

chmod +x "$DEST"/scripts/*.sh
chown -R bedrock:bedrock "$DEST"
systemctl daemon-reload
for INSTANCE in lobby survival pvp bedwars skywars; do
  systemctl enable "bedrock@$INSTANCE.service"
done
systemctl enable bedrock-backup-survival.timer

echo "Instalación base completada en $DEST"
echo "IMPORTANTE: edita $DEST/config/network.env antes de desplegar el addon del lobby."
