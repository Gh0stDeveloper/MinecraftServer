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
  mcserver network ensure-host
  mcserver network use-domain
  mcserver network use-ip

use-domain solo activa PUBLIC_DOMAIN cuando resuelve únicamente a PUBLIC_IP y
no publica un registro AAAA. ensure-host vuelve a la IPv4 si el host activo deja
de ser seguro para esta pasarela IPv4.
HELP
}

resolved_ipv4(){ getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u; }
resolved_ipv6(){ getent ahostsv6 "$1" 2>/dev/null | awk '{print $1}' | sort -u; }
domain_has_ipv6(){ [[ -n "${PUBLIC_DOMAIN:-}" ]] && [[ -n "$(resolved_ipv6 "$PUBLIC_DOMAIN")" ]]; }
domain_ok(){
  local -a addresses=()
  [[ -n "${PUBLIC_DOMAIN:-}" && -n "${PUBLIC_IP:-}" ]] || return 1
  mapfile -t addresses < <(resolved_ipv4 "$PUBLIC_DOMAIN")
  [[ ${#addresses[@]} -eq 1 && "${addresses[0]}" == "$PUBLIC_IP" ]] || return 1
  ! domain_has_ipv6
}
bedrock_probe(){
  local _instance="$1" port="$2" probe="$APP_DIR/scripts/bedrock-ping.py"
  [[ -f "$probe" ]] || probe="$SCRIPT_DIR/bedrock-ping.py"
  python3 "$probe" "$port" >/dev/null
}

apply_host(){
  local host="$1" mode="${2:-custom}" level was_active=0
  systemctl is-active --quiet bedrock@lobby.service 2>/dev/null && was_active=1 || true
  mkdir -p "$CONFIG_DIR"
  if grep -q '^PUBLIC_HOST=' "$CONFIG_FILE" 2>/dev/null; then sed -i "s|^PUBLIC_HOST=.*|PUBLIC_HOST=$host|" "$CONFIG_FILE"; else printf '\nPUBLIC_HOST=%s\n' "$host" >> "$CONFIG_FILE"; fi
  if grep -q '^TRANSFER_HOST_MODE=' "$CONFIG_FILE" 2>/dev/null; then sed -i "s|^TRANSFER_HOST_MODE=.*|TRANSFER_HOST_MODE=$mode|" "$CONFIG_FILE"; else printf 'TRANSFER_HOST_MODE=%s\n' "$mode" >> "$CONFIG_FILE"; fi
  chown root:bedrock "$CONFIG_FILE"; chmod 0640 "$CONFIG_FILE"
  source_config
  bash "$APP_DIR/scripts/render-lobby-config.sh"
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/lobby/server.properties" 2>/dev/null || true)"
  if [[ -n "$level" && -d "$INSTANCES_DIR/lobby/worlds/$level" ]]; then
    bash "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp" >/dev/null || true
    ((was_active)) && systemctl restart bedrock@lobby.service 2>/dev/null || true
  fi
  ok "PUBLIC_HOST=$host (modo=$mode)"
}

ensure_host(){
  if [[ "$TRANSFER_HOST_MODE" == domain ]]; then
    if domain_ok; then
      [[ "$PUBLIC_HOST" == "$PUBLIC_DOMAIN" ]] || apply_host "$PUBLIC_DOMAIN" domain
      ok "Host de transferencias por dominio: $PUBLIC_DOMAIN"
    else
      [[ -n "${PUBLIC_IP:-}" ]] || die 'El dominio activo es incompatible y PUBLIC_IP no está configurada.'
      warn "$PUBLIC_DOMAIN dejó de resolver de forma compatible; las transferencias vuelven a $PUBLIC_IP."
      apply_host "$PUBLIC_IP" ip
    fi
  elif [[ "$TRANSFER_HOST_MODE" == custom && -n "${PUBLIC_HOST:-}" ]]; then
    ok "Host de transferencias personalizado: $PUBLIC_HOST"
  elif [[ -z "${PUBLIC_IP:-}" ]]; then
    die 'PUBLIC_IP no configurada.'
  elif [[ "$PUBLIC_HOST" != "$PUBLIC_IP" || "$TRANSFER_HOST_MODE" != ip ]]; then
    warn "Las transferencias usarán la IPv4 pública para no depender del DNS del cliente."
    apply_host "$PUBLIC_IP" ip
  else
    ok "Host de transferencias por IPv4: $PUBLIC_HOST"
  fi
}

status(){
  printf '\nHost activo : %s\nIP pública  : %s\nDominio     : %s\n' "$PUBLIC_HOST" "${PUBLIC_IP:-?}" "${PUBLIC_DOMAIN:-?}"
  printf 'Modo transfer: %s\n' "$TRANSFER_HOST_MODE"
  if [[ -n "${PUBLIC_DOMAIN:-}" ]]; then
    printf 'DNS A       : '
    resolved_ipv4 "$PUBLIC_DOMAIN" | paste -sd, - || true
    printf '\n'
    printf 'DNS AAAA    : '
    resolved_ipv6 "$PUBLIC_DOMAIN" | paste -sd, - || true
    printf '\n'
  fi
}

service_state(){ systemctl is-active "bedrock@$1.service" 2>/dev/null || printf 'inactive'; }
verify(){
  local fail=0 instance port state
  status
  if [[ -z "${PUBLIC_DOMAIN:-}" ]]; then
    log "Dominio no configurado; la IP pública sigue siendo una dirección válida."
  elif domain_ok; then
    ok "DNS correcto: $PUBLIC_DOMAIN -> $PUBLIC_IP (sin AAAA incompatible)"
  else
    warn "DNS no apunta únicamente a $PUBLIC_IP o publica un AAAA que este gateway IPv4 no atiende."
    if [[ "$PUBLIC_HOST" == "$PUBLIC_DOMAIN" ]]; then
      fail=$((fail+1))
    else
      log "PUBLIC_HOST=$PUBLIC_HOST mantiene la conexión por IP mientras corriges el DNS."
    fi
  fi

  if systemctl is-active --quiet bedrock-gateway.service 2>/dev/null; then
    ok "Gateway RakNet activo para Lobby y Survival."
  else
    state="$(systemctl is-active bedrock-gateway.service 2>/dev/null || printf 'inactive')"
    warn "Gateway RakNet no está activo (estado=$state). Ejecuta: sudo mcserver bootstrap"
    fail=$((fail+1))
  fi

  if [[ -f "$APP_DIR/scripts/firewall-manager.sh" ]] && bash "$APP_DIR/scripts/firewall-manager.sh" check; then
    ok "Firewall local permite HTTP/HTTPS y puertos Bedrock administrados."
  else
    warn "Firewall local incompleto. Ejecuta: sudo mcserver firewall apply"
    fail=$((fail+1))
  fi

  while IFS=':' read -r instance port backend; do
    if [[ "$instance" == survival && -f "$STATE_DIR/survival-pending-import" ]]; then
      log "UDP/$port Survival pendiente de importación; es normal que aún no escuche."
      continue
    fi
    if [[ -n "$backend" ]] && ! udp_port_listening "$backend"; then
      state="$(service_state "$instance")"
      warn "Backend UDP/$backend no está escuchando ($instance; servicio=$state)."
      fail=$((fail+1))
      continue
    fi
    if udp_port_listening "$port"; then
      ok "UDP/$port escuchando ($instance)"
      if bedrock_probe "$instance" "$port"; then
        ok "UDP/$port responde con anuncio Bedrock/RakNet completo ($instance)"
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
lobby:$LOBBY_PORT:$LOBBY_BACKEND_PORT
survival:$SURVIVAL_PORT:$SURVIVAL_BACKEND_PORT
pvp:$PVP_PORT:
bedwars:$BEDWARS_PORT:
skywars:$SKYWARS_PORT:
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
  ensure-host) ensure_host;;
  use-domain) domain_ok || die "No activo el dominio: ${PUBLIC_DOMAIN:-sin-dominio} todavía no apunta únicamente a ${PUBLIC_IP:-sin-ip} o publica AAAA."; apply_host "$PUBLIC_DOMAIN" domain;;
  use-ip) [[ -n "${PUBLIC_IP:-}" ]] || die 'PUBLIC_IP no configurada.'; apply_host "$PUBLIC_IP" ip;;
  *) usage; exit 1;;
esac
