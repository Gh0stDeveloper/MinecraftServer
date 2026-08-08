#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
instance="${1:-}"
[[ " ${INSTANCES[*]} " == *" $instance "* ]] || die "Instancia inválida: ${instance:-vacía}"
engine="$(engine_for "$instance")"; target="$INSTANCES_DIR/$instance"
if [[ "$instance" == survival && -f "$STATE_DIR/survival-pending-import" ]]; then log "Survival permanece detenido hasta importar el mundo con: sudo mcserver import-survival /ruta/Mundo"; exit 0; fi
cd "$target"
case "$engine" in
  bds) [[ -x "$target/bedrock_server" ]] || die "BDS no instalado para $instance. Ejecuta: sudo mcserver update bds"; export LD_LIBRARY_PATH="$target${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; exec "$target/bedrock_server";;
  pnx) source_engines; jar="$PNX_CURRENT_LINK/powernukkitx-shaded.jar"; [[ -f "$jar" ]] || die "PowerNukkitX no instalado. Ejecuta: sudo mcserver update pnx"; command -v java >/dev/null || die "Java no está instalado."; exec java -Xms"$PNX_HEAP_MIN" -Xmx"$PNX_HEAP_MAX" -Dfile.encoding=UTF-8 -Djansi.passthrough=true -Dterminal.ansi=true -XX:+UseZGC -XX:+ZGenerational -XX:+UseStringDeduplication --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED --add-opens java.base/java.net=ALL-UNNAMED -jar "$jar";;
  *) die "Motor no soportado para $instance: $engine";;
esac
