#!/usr/bin/env bash
set -euo pipefail
BASE="/opt/bedrock-network"
[[ -f "$BASE/config/network.env" ]] || BASE="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE/config/network.env"
CFG="$BASE/addons/lobby_bp/scripts/config.js"

bool(){ [[ "$1" == 1 ]] && printf 'true' || printf 'false'; }
pvp_ready=0; bedwars_ready=0; skywars_ready=0
[[ -f "$BASE/instances/pvp/plugins/nexora-practice.jar" ]] && pvp_ready=1
[[ -f "$BASE/instances/bedwars/plugins/silentbedwars.jar" && -f "$BASE/instances/bedwars/worlds/world/level.dat" ]] && bedwars_ready=1
if [[ -f "$BASE/instances/skywars/plugins/powerskywars.jar" ]]; then
  shopt -s nullglob
  sky_maps=("$BASE"/instances/skywars/plugins/PowerSkywars/maps/*/level.dat)
  ((${#sky_maps[@]} > 0)) && skywars_ready=1
  shopt -u nullglob
fi

cat > "$CFG" <<EOF
export const NETWORK = Object.freeze({
  host: "${PUBLIC_HOST}",
  publicIp: "${PUBLIC_IP:-${PUBLIC_HOST}}",
  domain: "${PUBLIC_DOMAIN:-}",
  survival: ${SURVIVAL_PORT},
  pvp: ${PVP_PORT},
  bedwars: ${BEDWARS_PORT},
  skywars: ${SKYWARS_PORT},
  ready: Object.freeze({
    survival: true,
    pvp: $(bool "$pvp_ready"),
    bedwars: $(bool "$bedwars_ready"),
    skywars: $(bool "$skywars_ready")
  })
});
EOF

echo "Configuración del lobby actualizada: $PUBLIC_HOST (PvP=$pvp_ready BedWars=$bedwars_ready SkyWars=$skywars_ready)"
