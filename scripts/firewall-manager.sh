#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
source_config

CHAIN="BEDROCK-NETWORK"

usage(){ cat <<'HELP'
Uso:
  mcserver firewall apply
  mcserver firewall status
  mcserver firewall check

Abre únicamente en el firewall local:
  TCP 80,443
  UDP 19132-19136 (según network.env)

No modifica TCP/22 ni puede modificar la Security List/NSG del proveedor cloud.
HELP
}

ufw_active(){ command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; }

apply_ufw(){
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  local port
  for port in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do
    ufw allow "$port/udp" >/dev/null
  done
  ufw reload >/dev/null
  ok "UFW activo: HTTP/HTTPS y puertos Bedrock permitidos."
}

remove_input_jumps(){
  while iptables -w -C INPUT -j "$CHAIN" 2>/dev/null; do
    iptables -w -D INPUT -j "$CHAIN"
  done
}

apply_iptables(){
  command -v iptables >/dev/null 2>&1 || die "iptables no está instalado."
  iptables -w -N "$CHAIN" 2>/dev/null || true
  iptables -w -F "$CHAIN"
  iptables -w -A "$CHAIN" -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  local port
  for port in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do
    iptables -w -A "$CHAIN" -p udp --dport "$port" -j ACCEPT
  done
  iptables -w -A "$CHAIN" -j RETURN

  # La imagen de Oracle suele terminar INPUT con un REJECT global. El salto
  # administrado debe quedar antes de ese REJECT. No se toca la regla SSH/22.
  remove_input_jumps
  iptables -w -I INPUT 1 -j "$CHAIN"
  ok "Cadena $CHAIN insertada antes de las reglas de rechazo existentes."
}

persist_iptables(){
  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    log "Instalando persistencia de iptables..."
    command -v debconf-set-selections >/dev/null 2>&1 && {
      printf '%s\n' 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | debconf-set-selections
      printf '%s\n' 'iptables-persistent iptables-persistent/autosave_v6 boolean true' | debconf-set-selections
    }
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
  fi
  netfilter-persistent save >/dev/null
  systemctl enable netfilter-persistent.service >/dev/null 2>&1 || true
  ok "Reglas iptables guardadas para sobrevivir reinicios."
}

check_iptables(){
  iptables -w -C INPUT -j "$CHAIN" >/dev/null 2>&1 || return 1
  iptables -w -C "$CHAIN" -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT >/dev/null 2>&1 || return 1
  local port
  for port in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do
    iptables -w -C "$CHAIN" -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1 || return 1
  done
}

check_ufw(){
  local out port
  out="$(ufw status 2>/dev/null)"
  grep -Eq '(^|[[:space:]])80/tcp[[:space:]].*ALLOW' <<<"$out" || return 1
  grep -Eq '(^|[[:space:]])443/tcp[[:space:]].*ALLOW' <<<"$out" || return 1
  for port in "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"; do
    grep -Eq "(^|[[:space:]])${port}/udp[[:space:]].*ALLOW" <<<"$out" || return 1
  done
}

check(){
  if ufw_active; then check_ufw; else check_iptables; fi
}

status(){
  if ufw_active; then
    printf 'Firewall local: UFW activo\n'
    ufw status numbered
    check && ok "Puertos administrados presentes en UFW." || warn "Faltan reglas administradas en UFW. Ejecuta: sudo mcserver firewall apply"
  else
    printf 'Firewall local: iptables/nft (UFW inactivo)\n'
    if iptables -w -S "$CHAIN" >/dev/null 2>&1; then
      iptables -w -L "$CHAIN" -n -v --line-numbers
    else
      warn "Cadena $CHAIN no existe."
    fi
    check && ok "Reglas locales de Minecraft/web presentes." || warn "Faltan reglas locales. Ejecuta: sudo mcserver firewall apply"
  fi
  printf '\nNota: la Security List/NSG de Oracle debe permitir también TCP 80/443 y UDP %s,%s,%s,%s,%s.\n' "$LOBBY_PORT" "$SURVIVAL_PORT" "$PVP_PORT" "$BEDWARS_PORT" "$SKYWARS_PORT"
}

case "${1:-status}" in
  apply)
    if ufw_active; then apply_ufw; else apply_iptables; persist_iptables; fi
    check || die "Las reglas locales no quedaron aplicadas correctamente."
    ;;
  check) check;;
  status) status;;
  *) usage; exit 1;;
esac
