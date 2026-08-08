#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
source_config
fail=0
printf '\nDiagnóstico Bedrock Network\n---------------------------\n'
arch="$(uname -m)"; [[ "$arch" == x86_64 || "$arch" == amd64 ]] && ok "Arquitectura $arch" || { warn "Arquitectura $arch"; fail=$((fail+1)); }
command -v python3 >/dev/null && ok 'Python 3 disponible' || { warn 'Falta Python 3'; fail=$((fail+1)); }
[[ -x "$INSTANCES_DIR/lobby/bedrock_server" ]] && ok "BDS $(current_bds_version) instalado" || { warn 'BDS no instalado'; fail=$((fail+1)); }
[[ -f "$CONFIG_FILE" ]] && ok 'Configuración persistente presente' || { warn "Falta $CONFIG_FILE"; fail=$((fail+1)); }
if [[ -f "$INSTANCES_DIR/survival/server.properties" ]]; then assert_survival_safe || fail=$((fail+1)); fi
free="$(df -h "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')"; [[ -n "$free" ]] && ok "Espacio libre: $free"
"$APP_DIR/scripts/status.sh"
[[ $fail -eq 0 ]] && ok 'Diagnóstico sin bloqueos.' || die "Se encontraron $fail problema(s)."
