#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/socket-check.sh"
require_root
source_config
source_engines

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
bds_lan_discovery_disabled(){
  local instance="$1" file="$INSTANCES_DIR/$1/server.properties"
  [[ "$(engine_for "$instance")" == bds && -f "$file" ]] || return 1
  grep -Eq '^enable-lan-visibility=false([[:space:]]*)$' "$file"
}
bedrock_probe(){
  local instance="$1" port="$2" probe="$APP_DIR/scripts/bedrock-ping.py"
  [[ -f "$probe" ]] || probe="$SCRIPT_DIR/bedrock-ping.py"
  if bds_lan_discovery_disabled "$instance"; then
    python3 "$probe" "$port" --allow-bare >/dev/null
  else
    python3 "$probe" "$port" >/dev/null
  fi
}

apply_host(){
  local host="$1" level was_active=0
  systemctl is-active --quiet bedrock@lobby.service 2>/dev/null && was_active=1 || true
  mkdir -p "$CONFIG_DIR"
  if grep -q '^PUBLIC_HOST=' "$CONFIG_FILE" 2>/dev/null; then sed -i "s|^PUBLIC_HOST=.*|PUBLIC_HOST=$host|" "$CONFIG_FILE"; else printf '\nPUBLIC_HOST=%s\n' "$host" >> "$CONFIG_FILE"; fi
  chown root:bedrock "$CONFIG_FILE"; chmod 0640 "$CONFIG_FILE"
  source_config
  bash "$APP_DIR/scripts/render-lobby-config.sh"
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/lobby/server.properties" 2>/dev/null || true)"
  if [[ -n "$level" && -d "$INSTANCES_DIR/lobby/worlds/$level" ]]; then
    bash "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp" >/dev/null || true
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

service_state(){ systemctl is-active "bedrock@$1.service" 2>/dev/null || printf 'inactive'; }
verify(){
  local fail=0 instance port state
  status
  if domain_ok; then ok "DNS correcto: $PUBLIC_DOMAIN -> $PUBLIC_IP"; else warn "DNS no resuelve exactamente a $PUBLIC_IP."; fail=$((fail+1)); fi

  if [[ -f "$APP_DIR/scripts/firewall-manager.sh" ]] && bash "$APP_DIR/scripts/firewall-manager.sh" check; then
    ok "Firewall local permite HTTP/HTTPS y puertos Bedrock administrados."
  else
    warn "Firewall local incompleto. Ejecuta: sudo mcserver firewall apply"
    fail=$((fail+1))
  fi

  while IFS=':' read -r instance port; do
    if [[ "$instance" == survival && -f "$STATE_DIR/survival-pending-import" ]]; then
      log "UDP/$port Survival pendiente de importación; es normal que aún no escuche."
      continue
    fi
    if udp_port_listening "$port"; then
      ok "UDP/$port escuchando ($instance)"
      if bedrock_probe "$instance" "$port"; then
        if bds_lan_discovery_disabled "$instance"; then
          ok "UDP/$port responde por RakNet ($instance; anuncio LAN desactivado intencionalmente)"
        else
          ok "UDP/$port responde con anuncio Bedrock/RakNet completo ($instance)"
        fi
      else
        warn "UDP/$port escucha, pero no respondió correctamente al ping Bedrock/RakNet ($instance)."
        fail=$((fail+1))
      fi
    else
      state="$(service_state "$instance")"
      warn "UDP/$port no está escuchando ($instance; servicio=$state). Revisa: sudo mcserver logs $instance"
      fail=$((fail+1))
    fi
  done <<EOF
lobby:$LOBBY_PORT
survival:$SURVIVAL_PORT
pvp:$PVP_PORT
bedwars:$BEDWARS_PORT
skywars:$SKYWARS_PORT
EOF

  if tcp_port_listening "$WEB_PORT"; then
    ok "TCP/$WEB_PORT web escuchando"
  else
    state="$(systemctl is-active bedrock-web.service 2>/dev/null || printf 'inactive')"
    warn "TCP/$WEB_PORT web no está escuchando (bedrock-web=$state). Revisa: sudo mcserver web status"
    fail=$((fail+1))
  fi
  ((fail == 0)) || die "Verificación de red encontró $fail problema(s)."
}

case "${1:-status}" in
  status) status;;
  verify) verify;;
  use-domain) domain_ok || die "No activo el dominio: ${PUBLIC_DOMAIN:-sin-dominio} todavía no apunta a ${PUBLIC_IP:-sin-ip}."; apply_host "$PUBLIC_DOMAIN";;
  use-ip) [[ -n "${PUBLIC_IP:-}" ]] || die 'PUBLIC_IP no configurada.'; apply_host "$PUBLIC_IP";;
  *) usage; exit 1;;
esac
