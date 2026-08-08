#!/usr/bin/env bash
set -Eeuo pipefail

# Build one Nexora native plugin against the exact PowerNukkitX runtime JAR.
# PowerNukkitX 3 migrated its Java namespace from cn.nukkit.* to
# org.powernukkitx.*. The project sources remain readable against the historic
# API while this staging build performs the mechanical namespace migration in
# a disposable copy, never mutating /opt/bedrock-network/app.

if [[ $# -ne 3 ]]; then
  echo "Uso: $0 <directorio-plugin> <artefacto-relativo> <salida-jar>" >&2
  exit 2
fi

SRC="$(realpath "$1")"
ARTIFACT_REL="$2"
OUTPUT="$3"
PNX_API_JAR="${PNX_API_JAR:-}"

[[ -f "$SRC/pom.xml" ]] || { echo "Proyecto Maven inválido: $SRC" >&2; exit 1; }
[[ -n "$PNX_API_JAR" && -s "$PNX_API_JAR" ]] || { echo "PNX_API_JAR no apunta a un runtime PNX válido." >&2; exit 1; }
command -v mvn >/dev/null 2>&1 || { echo "Falta Maven." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Falta Python 3." >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/pnx-jar-validator.py" "$PNX_API_JAR" >/dev/null

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/nexora-pnx-plugin.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -a "$SRC/." "$STAGE/"
rm -rf "$STAGE/target"

while IFS= read -r -d '' source; do
  sed -i 's/cn\.nukkit\./org.powernukkitx./g' "$source"
done < <(find "$STAGE/src/main/java" -type f -name '*.java' -print0)

# Fail closed if a Java reference to the pre-PNX3 namespace remains.
if grep -R -n --include='*.java' 'cn\.nukkit\.' "$STAGE/src/main/java"; then
  echo "Quedaron referencias cn.nukkit.* después de la migración de staging." >&2
  exit 1
fi

(
  cd "$STAGE"
  PNX_API_JAR="$PNX_API_JAR" mvn -q -DskipTests package
)

BUILT="$STAGE/$ARTIFACT_REL"
[[ -s "$BUILT" ]] || { echo "Maven no generó $ARTIFACT_REL" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
install -m 0644 "$BUILT" "$OUTPUT"

echo "$OUTPUT"
