#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; source "$SCRIPT_DIR/lib.sh"; source_config; source_engines; fail=0
printf '\nDiagnóstico Nexora Network\n---------------------------\n'
arch="$(uname -m)"; [[ "$arch" == x86_64 || "$arch" == amd64 ]] && ok "Arquitectura $arch" || { warn "Arquitectura $arch"; fail=$((fail+1)); }
command -v python3 >/dev/null && ok 'Python 3 disponible' || { warn 'Falta Python 3'; fail=$((fail+1)); }
command -v ss >/dev/null && ok 'iproute2/ss disponible' || { warn 'Falta ss (iproute2)'; fail=$((fail+1)); }
validate_engine_layout || fail=$((fail+1))
if [[ -x "$INSTANCES_DIR/lobby/bedrock_server" ]]; then
  ok "BDS $(current_bds_version) instalado"
else
  warn 'BDS no instalado. Recupera con: sudo mcserver bootstrap'
  fail=$((fail+1))
fi
if instances_by_engine pnx | grep -q .; then
  java_major="$(java -version 2>&1 | sed -n '1s/.*version "\([0-9][0-9]*\).*/\1/p')"
  [[ "${java_major:-0}" -ge 21 ]] && ok "Java $java_major disponible para PNX" || { warn 'Se requiere Java 21+'; fail=$((fail+1)); }
  if [[ -f "$PNX_CURRENT_LINK/powernukkitx-shaded.jar" ]]; then
    ok "PowerNukkitX $(current_pnx_version) instalado"
  else
    warn 'PowerNukkitX no instalado. Recupera con: sudo mcserver bootstrap'
    fail=$((fail+1))
  fi
fi
[[ -f "$CONFIG_FILE" && -f "$ENGINES_FILE" ]] && ok 'Configuración persistente presente' || { warn 'Falta configuración persistente'; fail=$((fail+1)); }
if [[ -n "${PUBLIC_IP:-}" ]]; then ok "IP pública configurada: $PUBLIC_IP"; else warn 'PUBLIC_IP no configurada'; fail=$((fail+1)); fi
if [[ -n "${PUBLIC_DOMAIN:-}" ]]; then ok "Dominio configurado: $PUBLIC_DOMAIN"; else warn 'PUBLIC_DOMAIN no configurado'; fi
if [[ -f "$APP_DIR/scripts/firewall-manager.sh" ]] && bash "$APP_DIR/scripts/firewall-manager.sh" check; then
  ok 'Firewall local administrado correctamente'
else
  warn 'Firewall local incompleto. Ejecuta: sudo mcserver firewall apply'
  fail=$((fail+1))
fi
if [[ -f "$INSTANCES_DIR/survival/server.properties" ]]; then assert_survival_safe || fail=$((fail+1)); fi
if [[ -f "$APP_DIR/scripts/plugin-manager.sh" ]] && ! bash "$APP_DIR/scripts/plugin-manager.sh" doctor; then fail=$((fail+1)); fi
if [[ -f "$APP_DIR/scripts/minigame-manager.sh" ]]; then bash "$APP_DIR/scripts/minigame-manager.sh" status || true; fi
if systemctl is-active --quiet bedrock-gateway.service 2>/dev/null; then
  ok 'Gateway RakNet activo'
else
  warn 'Gateway RakNet inactivo. Ejecuta: sudo mcserver bootstrap'
  fail=$((fail+1))
fi
free="$(df -h "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')"; [[ -n "$free" ]] && ok "Espacio libre: $free"
bash "$APP_DIR/scripts/status.sh"; [[ $fail -eq 0 ]] && ok 'Diagnóstico sin bloqueos.' || die "Se encontraron $fail problema(s)."
