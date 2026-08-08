#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; source "$SCRIPT_DIR/lib.sh"; source_config; source_engines; fail=0
printf '\nDiagnóstico Bedrock Network\n---------------------------\n'
arch="$(uname -m)"; [[ "$arch" == x86_64 || "$arch" == amd64 ]] && ok "Arquitectura $arch" || { warn "Arquitectura $arch"; fail=$((fail+1)); }
command -v python3 >/dev/null && ok 'Python 3 disponible' || { warn 'Falta Python 3'; fail=$((fail+1)); }
validate_engine_layout || fail=$((fail+1))
[[ -x "$INSTANCES_DIR/lobby/bedrock_server" ]] && ok "BDS $(current_bds_version) instalado" || { warn 'BDS no instalado'; fail=$((fail+1)); }
if instances_by_engine pnx | grep -q .; then java_major="$(java -version 2>&1 | sed -n '1s/.*version "\([0-9][0-9]*\).*/\1/p')"; [[ "${java_major:-0}" -ge 21 ]] && ok "Java $java_major disponible para PNX" || { warn 'Se requiere Java 21+'; fail=$((fail+1)); }; [[ -f "$PNX_CURRENT_LINK/powernukkitx-shaded.jar" ]] && ok "PowerNukkitX $(current_pnx_version) instalado" || { warn 'PowerNukkitX no instalado'; fail=$((fail+1)); }; fi
[[ -f "$CONFIG_FILE" && -f "$ENGINES_FILE" ]] && ok 'Configuración persistente presente' || { warn 'Falta configuración persistente'; fail=$((fail+1)); }
if [[ -f "$INSTANCES_DIR/survival/server.properties" ]]; then assert_survival_safe || fail=$((fail+1)); fi
if [[ -x "$APP_DIR/scripts/plugin-manager.sh" ]] && ! "$APP_DIR/scripts/plugin-manager.sh" doctor; then fail=$((fail+1)); fi
free="$(df -h "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')"; [[ -n "$free" ]] && ok "Espacio libre: $free"
"$APP_DIR/scripts/status.sh"; [[ $fail -eq 0 ]] && ok 'Diagnóstico sin bloqueos.' || die "Se encontraron $fail problema(s)."
