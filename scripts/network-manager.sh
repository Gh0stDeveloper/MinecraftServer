#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
source_config

usage(){ cat <<'HELP'
Uso:
  mcserver network status
  mcserver network verify
  mcserver network use-domain
  mcserver network use-ip

use-domain solo activa PUBLIC_DOMAIN cuando resuelve exactamente a PUBLIC_IP.
HELP
}

resolved_ipv4(){ getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u; }
domain_ok(){ [[ -n "${PUBLIC_DOMAIN:-}" && -n "${PUBLIC_IP:-}" ]] && resolved_ipv4 "$PUBLIC_DOMAIN" | grep -Fxq "$PUBLIC_IP"; }

apply_host(){
  local host="$1" level was_active=0
  systemctl is-active --quiet bedrock@lobby.service 2>/dev/null && was_active=1 || true
  if grep -q '^PUBLIC_HOST=' "$CONFIG_FILE"; then sed -i "s|^PUBLIC_HOST=.*|PUBLIC_HOST=$host|" "$CONFIG_FILE"; else printf '\nPUBLIC_HOST=%s\n' "$host" >> "$CONFIG_FILE"; fi
  source_config
  "$APP_DIR/scripts/render-lobby-config.sh"
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/lobby/server.properties" 2>/dev/null || true)"
  if [[ -n "$level" && -d "$INSTANCES_DIR/lobby/worlds/$level" ]]; then
    "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp" >/dev/null || true
    ((was_active)) && systemctl restart bedrock@lobby.service 2>/dev/null || true
  fi
  ok "PUBLIC_HOST=$host"
}

status(){
  printf '\nHost activo : %s\nIP pública  : %s\nDominio     : %s\n' "$PUBLIC_HOST" "${PUBLIC_IP:-?}" "${PUBLIC_DOMAIN:-?}"
  if [[ -n "${PUBLIC_DOMAIN:-}" ]]; then
    printf 'DNS actual  : '
    resolved_ipv4 "$PUBLIC_DOMAIN" | paste -sd, - || true
    printf '\n'
  fi
}

verify(){
  local fail=0
  status
  if domain_ok; then ok "DNS correcto: $PUBLIC_DOMAIN -> $PUBLIC_IP"; else warn "DNS no resuelve exactamente a $PUBLIC_IP."; fail=$((fail+1)); fi
  for port in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do
    if ss -H -lun 2>/dev/null | awk '{print $5}' | grep -Eq "(:|\])${port}$"; then ok "UDP/$port escuchando"; else warn "UDP/$port no está escuchando localmente."; fail=$((fail+1)); fi
  done
  if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\])${WEB_PORT}$"; then ok "TCP/$WEB_PORT web escuchando"; else warn "TCP/$WEB_PORT web no está escuchando."; fail=$((fail+1)); fi
  ((fail == 0)) || die "Verificación de red encontró $fail problema(s)."
}

case "${1:-status}" in
  status) status;;
  verify) verify;;
  use-domain) domain_ok || die "No activo el dominio: ${PUBLIC_DOMAIN:-sin-dominio} todavía no apunta a ${PUBLIC_IP:-sin-ip}."; apply_host "$PUBLIC_DOMAIN";;
  use-ip) [[ -n "${PUBLIC_IP:-}" ]] || die 'PUBLIC_IP no configurada.'; apply_host "$PUBLIC_IP";;
  *) usage; exit 1;;
esac
