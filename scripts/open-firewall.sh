#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Usa sudo." >&2; exit 1; fi
for PORT in 19132 19133 19134 19135 19136; do
  ufw allow "$PORT/udp"
done
ufw status verbose
