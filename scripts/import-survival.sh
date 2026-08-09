#!/usr/bin/env bash
set -Eeuo pipefail

CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 [--check] /ruta/Mundo|/ruta/Mundo.zip|/ruta/Mundo.mcworld" >&2
  exit 1
fi
if (( ! CHECK_ONLY )) && [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Usa sudo." >&2
  exit 1
fi

INPUT="$1"
[[ -e "$INPUT" ]] || { echo "No existe: $INPUT" >&2; exit 1; }
INPUT="$(realpath "$INPUT")"
TMP=""
SRC=""
cleanup(){ [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"; }
trap cleanup EXIT

valid_world(){ [[ -d "$1" && -f "$1/level.dat" && -d "$1/db" ]]; }

resolve_world(){
  local input="$1" candidate count=0
  if [[ -d "$input" ]]; then
    valid_world "$input" || { echo "ERROR: el directorio no parece un mundo Bedrock (requiere level.dat y db/)." >&2; exit 1; }
    SRC="$input"
    return
  fi

  case "${input,,}" in
    *.zip|*.mcworld) ;;
    *) echo "ERROR: archivo no soportado. Usa .zip o .mcworld." >&2; exit 1;;
  esac
  command -v unzip >/dev/null || { echo "ERROR: falta unzip." >&2; exit 1; }

  # Validar primero la estructura ZIP central. Esto evita mensajes duplicados de
  # zipinfo/unzip y falla antes de crear temporales o tocar Survival.
  if ! unzip -tqq "$input" >/dev/null 2>&1; then
    echo "ERROR: el archivo no es un ZIP/.mcworld válido. Puede estar corrupto, incompleto, dividido en varias partes o ser un .7z/.rar renombrado como .zip." >&2
    exit 1
  fi

  # Rechazar rutas absolutas o traversal antes de extraer un archivo recibido del teléfono.
  if unzip -Z1 "$input" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    echo "ERROR: el archivo contiene rutas inseguras." >&2
    exit 1
  fi

  TMP="$(mktemp -d /tmp/mcserver-survival.XXXXXX)"
  echo "Extrayendo $(basename "$input")..."
  unzip -q "$input" -d "$TMP"

  if valid_world "$TMP"; then
    SRC="$TMP"
    return
  fi

  while IFS= read -r candidate; do
    candidate="$(dirname "$candidate")"
    if valid_world "$candidate"; then
      SRC="$candidate"
      count=$((count + 1))
    fi
  done < <(find "$TMP" -mindepth 1 -maxdepth 6 -type f -name level.dat -print)

  if (( count == 0 )); then
    echo "ERROR: el ZIP/.mcworld no contiene un mundo Bedrock válido (level.dat + db/)." >&2
    exit 1
  fi
  if (( count > 1 )); then
    echo "ERROR: el archivo contiene más de un mundo Bedrock; deja solo el Survival que deseas importar." >&2
    exit 1
  fi
}

resolve_world "$INPUT"
echo "Mundo Bedrock detectado: $SRC"
if (( CHECK_ONLY )); then
  echo "[OK] El archivo/directorio es válido para import-survival."
  exit 0
fi

BASE=/opt/bedrock-network
INSTANCE="$BASE/instances/survival"
DEST="$INSTANCE/worlds/SurvivalWorld"
BACKUPS="$BASE/backups/imports"
STAMP="$(date +%Y%m%d-%H%M%S)"

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
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
chown -R bedrock:bedrock "$DEST"

sed -i 's/^allow-cheats=.*/allow-cheats=false/' "$INSTANCE/server.properties"
sed -i 's/^force-gamemode=.*/force-gamemode=false/' "$INSTANCE/server.properties"
sed -i 's/^gamemode=.*/gamemode=survival/' "$INSTANCE/server.properties"
sed -i 's/^online-mode=.*/online-mode=true/' "$INSTANCE/server.properties"
sed -i 's/^allow-list=.*/allow-list=true/' "$INSTANCE/server.properties"
sed -i 's/^level-name=.*/level-name=SurvivalWorld/' "$INSTANCE/server.properties"
if [[ -f "$BASE/config/engines.env" ]]; then
  sed -i 's/^SURVIVAL_ENGINE=.*/SURVIVAL_ENGINE=bds/' "$BASE/config/engines.env"
fi
rm -f "$BASE/state/survival-pending-import"

cat <<EOF2

Importación terminada.
PROTECCIÓN DE LOGROS:
- level.dat fue copiado tal cual.
- motor BDS oficial.
- allow-cheats=false
- force-gamemode=false
- online-mode=true
- allow-list=true
- ningún plugin PNX se instala en Survival.

Destino instalado:
$DEST
EOF2
