#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then echo "Usa sudo." >&2; exit 1; fi
if [[ $# -ne 2 ]]; then echo "Uso: $0 <instancia> <ruta-addon>" >&2; exit 1; fi

INSTANCE="$1"
ADDON_SRC="$(realpath "$2")"
BASE="${BEDROCK_ROOT:-/opt/bedrock-network}"
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

python3 - "$ADDON_SRC/manifest.json" "$WORLD/world_behavior_packs.json" "$TARGET/config" <<'PY2'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
world_packs = Path(sys.argv[2])
config_dir = Path(sys.argv[3])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
header = manifest["header"]
entry = {"pack_id": header["uuid"], "version": header["version"]}

try:
    data = json.loads(world_packs.read_text(encoding="utf-8"))
except Exception:
    data = []
data = [x for x in data if x.get("pack_id") != entry["pack_id"]]
data.append(entry)
world_packs.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

# BDS requires explicit module permissions for script packs. Keep permissions
# constrained to the Mojang modules actually declared by this addon.
allowed = sorted({
    dep.get("module_name")
    for dep in manifest.get("dependencies", [])
    if isinstance(dep, dict) and str(dep.get("module_name", "")).startswith("@minecraft/")
})
script_ids = [
    module.get("uuid")
    for module in manifest.get("modules", [])
    if isinstance(module, dict) and module.get("type") == "script" and module.get("uuid")
]

def merge_permissions(path: Path) -> None:
    try:
        current = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(current, dict):
            current = {}
    except Exception:
        current = {}
    current_allowed = current.get("allowed_modules", [])
    if not isinstance(current_allowed, list):
        current_allowed = []
    current["allowed_modules"] = sorted(set(current_allowed) | set(allowed))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(current, indent=2) + "\n", encoding="utf-8")

if allowed and script_ids:
    # Minimal global defaults plus a per-script-module policy. The UUID policy
    # is the important part and keeps future script packs isolated.
    merge_permissions(config_dir / "default" / "permissions.json")
    for script_id in script_ids:
        merge_permissions(config_dir / script_id / "permissions.json")
PY2

chown -R bedrock:bedrock "$TARGET/behavior_packs" "$WORLD" "$TARGET/config"
echo "Addon $PACK_NAME instalado en $INSTANCE/$LEVEL_NAME"
