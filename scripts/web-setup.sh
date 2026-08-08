#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
ACTION="${1:-status}"
DOMAIN="${2:-}"
TOKEN_HASH_FILE="$CONFIG_DIR/web-admin.token.sha256"

resolved_ipv4(){ getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u; }
domain_matches_public_ip(){ [[ -n "$1" && -n "${PUBLIC_IP:-}" ]] || return 1; resolved_ipv4 "$1" | grep -Fxq "$PUBLIC_IP"; }
require_correct_dns(){
  local domain="$1" actual
  [[ -n "${PUBLIC_IP:-}" ]] || return 0
  if ! domain_matches_public_ip "$domain"; then
    actual="$(resolved_ipv4 "$domain" | paste -sd, - || true)"; [[ -n "$actual" ]] || actual="sin IPv4"
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
new_admin_token(){
  local token hash
  if command -v openssl >/dev/null 2>&1; then token="$(openssl rand -hex 24)"; else token="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"; fi
  hash="$(printf '%s' "$token" | sha256sum | awk '{print $1}')"
  printf '%s\n' "$hash" > "$TOKEN_HASH_FILE"
  chown root:bedrock "$TOKEN_HASH_FILE"; chmod 0640 "$TOKEN_HASH_FILE"
  systemctl restart bedrock-web.service 2>/dev/null || true
  printf '\n[OK] Nuevo token administrativo web generado.\nGuárdalo: se muestra solo ahora.\n\n%s\n\nPanel: https://%s/admin.html\n' "$token" "${PUBLIC_DOMAIN:-$PUBLIC_HOST}"
}

case "$ACTION" in
  status) systemctl status bedrock-web.service --no-pager || true;;
  restart) systemctl restart bedrock-web.service; ok 'Web reiniciada.';;
  admin-token) new_admin_token;;
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
    client_max_body_size ${WEB_MAX_UPLOAD_MB}m;
    location / {
        proxy_pass http://127.0.0.1:$WEB_PORT;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
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
      EMAIL="${3:-}"; [[ -n "$EMAIL" ]] || die 'Uso: mcserver web https [DOMINIO] EMAIL'
      ufw allow 443/tcp >/dev/null 2>&1 || true
      apt-get install -y certbot python3-certbot-nginx
      certbot --nginx --non-interactive --agree-tos --redirect -m "$EMAIL" -d "$DOMAIN"
    fi
    ok "Web configurada para $DOMAIN";;
  *) die 'Uso: web-setup.sh status|restart|admin-token|domain [DOMINIO]|https [DOMINIO] EMAIL';;
esac
