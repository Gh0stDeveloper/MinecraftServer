#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
ACTION="${1:-status}"
DOMAIN="${2:-}"

resolved_ipv4(){ getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u; }
domain_matches_public_ip(){
  [[ -n "$1" && -n "${PUBLIC_IP:-}" ]] || return 1
  resolved_ipv4 "$1" | grep -Fxq "$PUBLIC_IP"
}
require_correct_dns(){
  local domain="$1" actual
  [[ -n "${PUBLIC_IP:-}" ]] || return 0
  if ! domain_matches_public_ip "$domain"; then
    actual="$(resolved_ipv4 "$domain" | paste -sd, - || true)"
    [[ -n "$actual" ]] || actual="sin IPv4"
    die "DNS incorrecto para $domain: resuelve a $actual, pero esta VPS usa $PUBLIC_IP. No modificaré Nginx/HTTPS con un dominio ajeno."
  fi
}
ensure_backend(){
  systemctl enable --now bedrock-web.service >/dev/null 2>&1 || true
  sleep 1
  if ! systemctl is-active --quiet bedrock-web.service; then
    warn "bedrock-web.service no pudo iniciar."
    journalctl -u bedrock-web.service -n 20 --no-pager >&2 || true
    die "La web backend debe funcionar antes de configurar Nginx/HTTPS."
  fi
}

case "$ACTION" in
  status)
    systemctl status bedrock-web.service --no-pager || true
    ;;
  restart)
    systemctl restart bedrock-web.service
    ok 'Web reiniciada.'
    ;;
  domain|https)
    [[ -n "$DOMAIN" ]] || DOMAIN="${PUBLIC_DOMAIN:-}"
    [[ -n "$DOMAIN" ]] || die "Indica el dominio o configura PUBLIC_DOMAIN."
    require_correct_dns "$DOMAIN"
    ensure_backend

    cat > /etc/nginx/sites-available/bedrock-network <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:$WEB_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
    ln -sfn /etc/nginx/sites-available/bedrock-network /etc/nginx/sites-enabled/bedrock-network
    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx
    ufw allow 80/tcp >/dev/null 2>&1 || true

    if [[ "$ACTION" == https ]]; then
      EMAIL="${3:-}"
      [[ -n "$EMAIL" ]] || die 'Uso: mcserver web https [DOMINIO] EMAIL'
      ufw allow 443/tcp >/dev/null 2>&1 || true
      apt-get install -y certbot python3-certbot-nginx
      certbot --nginx --non-interactive --agree-tos --redirect -m "$EMAIL" -d "$DOMAIN"
    fi
    ok "Web configurada para $DOMAIN"
    ;;
  *) die 'Uso: web-setup.sh status|restart|domain [DOMINIO]|https [DOMINIO] EMAIL';;
esac
