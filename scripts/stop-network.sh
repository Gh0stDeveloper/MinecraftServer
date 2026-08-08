#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Usa sudo." >&2; exit 1; fi
for INSTANCE in skywars bedwars pvp survival lobby; do
  systemctl stop "bedrock@$INSTANCE.service" || true
done
