#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Usa sudo." >&2; exit 1; fi
if [[ $# -ne 2 ]]; then echo "Uso: $0 <instancia> <ruta-addon>" >&2; exit 1; fi
INSTANCE="$1"
ADDON_SRC="$(realpath "$2")"
BASE=/opt/bedrock-network
TARGET="$BASE/instances/$INSTANCE"
[[ -d "$TARGET" ]] || { echo "Instancia inexistente: $INSTANCE" >&2; exit 1; }
[[ -f "$ADDON_SRC/manifest.json" ]] || { echo "manifest.json no encontrado" >&2; exit 1; }

PACK_NAME="$(basename "$ADDON_SRC")"
mkdir -p "$TARGET/behavior_packs/$PACK_NAME"
rsync -a --delete "$ADDON_SRC/" "$TARGET/behavior_packs/$PACK_NAME/"

LEVEL_NAME="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$TARGET/server.properties")"
WORLD="$TARGET/worlds/$LEVEL_NAME"
if [[ ! -d "$WORLD" ]]; then
  echo "El mundo $LEVEL_NAME todavía no existe. Inicia la instancia una vez, detenla y vuelve a ejecutar este script." >&2
  exit 2
fi

python3 - "$ADDON_SRC/manifest.json" "$WORLD/world_behavior_packs.json" <<'PY2'
import json,sys
manifest=json.load(open(sys.argv[1],encoding='utf-8'))
header=manifest['header']
entry={'pack_id': header['uuid'], 'version': header['version']}
out=sys.argv[2]
try:
    data=json.load(open(out,encoding='utf-8'))
except Exception:
    data=[]
data=[x for x in data if x.get('pack_id') != entry['pack_id']]
data.append(entry)
json.dump(data,open(out,'w',encoding='utf-8'),indent=2)
PY2
chown -R bedrock:bedrock "$TARGET/behavior_packs" "$WORLD"
echo "Addon $PACK_NAME instalado en $INSTANCE/$LEVEL_NAME"
