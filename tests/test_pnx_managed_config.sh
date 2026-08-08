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
check_instance bedwars 19135 BedWars
check_instance skywars 19136 SkyWars

# No managed PNX minigame may ever fall back to the Lobby port/default world.
! grep -R -Fxq '  port: 19132' "$TEST_ROOT/instances/pvp/pnx.yml" "$TEST_ROOT/instances/bedwars/pnx.yml" "$TEST_ROOT/instances/skywars/pnx.yml"
! grep -R -Fxq '  defaultLevelName: "world"' "$TEST_ROOT/instances/pvp/pnx.yml" "$TEST_ROOT/instances/bedwars/pnx.yml" "$TEST_ROOT/instances/skywars/pnx.yml"

echo "Managed PowerNukkitX port/level regression passed."
