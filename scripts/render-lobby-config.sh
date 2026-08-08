#!/usr/bin/env bash
set -euo pipefail
BASE="/opt/bedrock-network"
[[ -f "$BASE/config/network.env" ]] || BASE="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE/config/network.env"
CFG="$BASE/addons/lobby_bp/scripts/config.js"
cat > "$CFG" <<EOF
export const NETWORK = Object.freeze({
  host: "${PUBLIC_HOST}",
  survival: ${SURVIVAL_PORT},
  pvp: ${PVP_PORT},
  bedwars: ${BEDWARS_PORT},
  skywars: ${SKYWARS_PORT}
});
EOF

echo "Configuración del lobby actualizada: $PUBLIC_HOST"
