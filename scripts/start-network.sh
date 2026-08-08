#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Usa sudo." >&2; exit 1; fi
for INSTANCE in lobby survival pvp bedwars skywars; do
  systemctl start "bedrock@$INSTANCE.service"
done
systemctl start bedrock-backup-survival.timer
systemctl --no-pager --full status bedrock@lobby.service || true
