#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/nexora-pnx-config.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

if ! getent group bedrock >/dev/null 2>&1; then groupadd --system bedrock; fi
if ! id bedrock >/dev/null 2>&1; then useradd --system --gid bedrock --no-create-home --shell /usr/sbin/nologin bedrock; fi

BEDROCK_ROOT="$TEST_ROOT" NO_COLOR=1 bash "$ROOT/scripts/engine-manager.sh" prepare >/dev/null

check_instance(){
  local instance="$1" port="$2" level="$3"
  local yaml="$TEST_ROOT/instances/$instance/pnx.yml"
  local props="$TEST_ROOT/instances/$instance/server.properties"
  [[ -f "$yaml" && -f "$props" ]]
  grep -Fxq "  port: $port" "$yaml"
  grep -Fxq "  defaultLevelName: \"$level\"" "$yaml"
  grep -Fxq "server-port=$port" "$props"
  grep -Fxq "level-name=$level" "$props"
}

check_instance pvp 19134 PvP
# `world` is intentional here: the pinned SilentBedwars fallback opens that
# level explicitly, so the managed BedWars instance preserves compatibility.
check_instance bedwars 19135 world
check_instance skywars 19136 SkyWars

# No managed PNX minigame may ever inherit the Lobby UDP port.
! grep -R -Fxq '  port: 19132' "$TEST_ROOT/instances/pvp/pnx.yml" "$TEST_ROOT/instances/bedwars/pnx.yml" "$TEST_ROOT/instances/skywars/pnx.yml"

echo "Managed PowerNukkitX port/level regression passed."
