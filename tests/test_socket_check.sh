#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/ss" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" -lun "* ]]; then
  cat <<'OUT'
UNCONN 0 0 0.0.0.0:19132 198.51.100.20:19133
UNCONN 0 0 [::]:19134 [::]:*
OUT
elif [[ " $* " == *" -ltn "* ]]; then
  cat <<'OUT'
LISTEN 0 128 127.0.0.1:8080 0.0.0.0:*
OUT
fi
EOF
chmod +x "$TMP/ss"
PATH="$TMP:$PATH"
source "$ROOT/scripts/socket-check.sh"

udp_port_listening 19132
udp_port_listening 19134
! udp_port_listening 19133  # 19133 appears only in the peer column; must not match.
tcp_port_listening 8080
! tcp_port_listening 443

echo "Socket detection regression passed."

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  bash "$ROOT/tests/test_pnx_managed_config.sh"
else
  sudo bash "$ROOT/tests/test_pnx_managed_config.sh"
fi
