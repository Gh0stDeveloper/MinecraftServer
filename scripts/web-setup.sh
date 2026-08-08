#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
ACTION="${1:-status}"
DOMAIN="${2:-}"
case "$ACTION" in
  status) systemctl status bedrock-web.service --no-pager || true;;
  restart) systemctl restart bedrock-web.service; ok 'Web reiniciada.';;
  domain|https)
    [[ -n "$DOMAIN" ]] || die "Indica el dominio."
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
    nginx -t; systemctl enable --now nginx; systemctl reload nginx; ufw allow 80/tcp >/dev/null 2>&1 || true
    if [[ "$ACTION" == https ]]; then
      EMAIL="${3:-}"; [[ -n "$EMAIL" ]] || die 'Uso: mcserver web https DOMINIO EMAIL'
      apt-get install -y certbot python3-certbot-nginx
      certbot --nginx --non-interactive --agree-tos --redirect -m "$EMAIL" -d "$DOMAIN"
    fi
    ok "Web configurada para $DOMAIN";;
  *) die 'Uso: web-setup.sh status|restart|domain DOMINIO|https DOMINIO EMAIL';;
esac
