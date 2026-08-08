#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Usa sudo." >&2; exit 1; fi
if [[ $# -ne 1 ]]; then echo "Uso: $0 /ruta/al/mundo" >&2; exit 1; fi
SRC="$(realpath "$1")"
BASE=/opt/bedrock-network
INSTANCE="$BASE/instances/survival"
DEST="$INSTANCE/worlds/SurvivalWorld"
BACKUPS="$BASE/backups/imports"
STAMP="$(date +%Y%m%d-%H%M%S)"

[[ -d "$SRC" ]] || { echo "No existe directorio: $SRC" >&2; exit 1; }
[[ -f "$SRC/level.dat" ]] || { echo "ERROR: no parece un mundo Bedrock: falta level.dat" >&2; exit 1; }
[[ -d "$SRC/db" ]] || { echo "ERROR: no parece un mundo Bedrock: falta db/" >&2; exit 1; }

if systemctl is-active --quiet bedrock@survival.service; then
  echo "Deteniendo Survival antes de importar..."
  systemctl stop bedrock@survival.service
fi

mkdir -p "$BACKUPS" "$INSTANCE/worlds"
if [[ -d "$DEST" ]]; then
  echo "Respaldando mundo Survival existente..."
  tar -C "$INSTANCE/worlds" -czf "$BACKUPS/SurvivalWorld-before-import-$STAMP.tar.gz" SurvivalWorld
fi

echo "Copiando mundo sin modificar level.dat..."
rm -rf "$DEST.new"
mkdir -p "$DEST.new"
rsync -aH --info=progress2 "$SRC/" "$DEST.new/"
mv "$DEST.new" "$DEST"
chown -R bedrock:bedrock "$DEST"

sed -i 's/^allow-cheats=.*/allow-cheats=false/' "$INSTANCE/server.properties"
sed -i 's/^force-gamemode=.*/force-gamemode=false/' "$INSTANCE/server.properties"
sed -i 's/^gamemode=.*/gamemode=survival/' "$INSTANCE/server.properties"
sed -i 's/^online-mode=.*/online-mode=true/' "$INSTANCE/server.properties"
sed -i 's/^allow-list=.*/allow-list=true/' "$INSTANCE/server.properties"
sed -i 's/^level-name=.*/level-name=SurvivalWorld/' "$INSTANCE/server.properties"

cat <<EOF

Importación terminada.

PROTECCIÓN DE LOGROS:
- level.dat fue copiado tal cual.
- allow-cheats=false
- force-gamemode=false
- online-mode=true
- allow-list=true
- no se instaló ningún Behavior Pack de esta red en Survival.

Antes de iniciar, añade los Gamertags permitidos a:
  $INSTANCE/allowlist.json

EOF
