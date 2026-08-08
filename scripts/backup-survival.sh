#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/bedrock-network
INSTANCE="$BASE/instances/survival"
WORLD="$INSTANCE/worlds/SurvivalWorld"
DEST="$BASE/backups/survival"
STAMP="$(date +%Y%m%d-%H%M%S)"
WAS_ACTIVE=0

[[ -d "$WORLD" ]] || { echo "No existe $WORLD; omitiendo backup."; exit 0; }
mkdir -p "$DEST"

if systemctl is-active --quiet bedrock@survival.service; then
  WAS_ACTIVE=1
  systemctl stop bedrock@survival.service
fi

trap 'if [[ "$WAS_ACTIVE" == 1 ]]; then systemctl start bedrock@survival.service || true; fi' EXIT

tar -C "$INSTANCE/worlds" -czf "$DEST/SurvivalWorld-$STAMP.tar.gz" SurvivalWorld

mapfile -t OLD < <(ls -1t "$DEST"/SurvivalWorld-*.tar.gz 2>/dev/null | tail -n +31 || true)
if ((${#OLD[@]})); then rm -f "${OLD[@]}"; fi

echo "Backup creado: $DEST/SurvivalWorld-$STAMP.tar.gz"
