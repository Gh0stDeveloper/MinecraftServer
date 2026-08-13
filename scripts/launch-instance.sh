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
  pnx)
    source_engines
    jar="$PNX_CURRENT_LINK/powernukkitx-shaded.jar"
    [[ -f "$jar" ]] || die "PowerNukkitX no instalado. Ejecuta: sudo mcserver update pnx"
    command -v java >/dev/null || die "Java no está instalado."

    # PNX 3 importa nukkit.yml antes que pnx.yml. Un archivo legacy puede
    # restaurar settings.port=19132 y hacer que el minijuego choque con Lobby.
    # Se retira en cada arranque, no únicamente durante bootstrap/prepare.
    rm -f "$target/nukkit.yml"
    [[ -f "$target/pnx.yml" ]] || die "Falta pnx.yml para $instance. Ejecuta: sudo mcserver engine prepare $instance"
    expected_port="$(awk -F= '$1=="server-port"{print substr($0,index($0,"=")+1); exit}' "$target/server.properties")"
    configured_port="$(awk '/^settings:/{inside=1; next} inside && /^[^[:space:]]/{inside=0} inside && /^  port:[[:space:]]*/{print $2; exit}' "$target/pnx.yml")"
    [[ "$expected_port" =~ ^[0-9]+$ ]] || die "server-port inválido para $instance: ${expected_port:-vacío}"
    if [[ "$configured_port" != "$expected_port" ]]; then
      warn "$instance tenía settings.port=${configured_port:-vacío}; se corrige a $expected_port antes de iniciar."
      if [[ -n "$configured_port" ]]; then
        sed -i "0,/^  port:/s|^  port:.*$|  port: $expected_port|" "$target/pnx.yml"
      else
        sed -i "/^settings:[[:space:]]*$/a\\  port: $expected_port" "$target/pnx.yml"
      fi
    fi

    # PowerNukkitX devuelve código 0 incluso ante algunos abortos fatales de
    # red. El wrapper convierte esa salida inesperada en fallo para que systemd
    # no deje el servicio como inactive (dead) sin reintentar ni alertar.
    set +e
    java -Xms"$PNX_HEAP_MIN" -Xmx"$PNX_HEAP_MAX" -Dfile.encoding=UTF-8 -Djansi.passthrough=true -Dterminal.ansi=true -XX:+UseZGC -XX:+ZGenerational -XX:+UseStringDeduplication --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED --add-opens java.base/java.net=ALL-UNNAMED -jar "$jar"
    rc=$?
    set -e
    (( rc != 0 )) || die "PowerNukkitX terminó inesperadamente con código 0; systemd lo reiniciará."
    exit "$rc"
    ;;
  *) die "Motor no soportado para $instance: $engine";;
esac
