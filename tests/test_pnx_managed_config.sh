#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/nexora-pnx-config.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_PATH="$PATH"
if ! getent group bedrock >/dev/null 2>&1 || ! id bedrock >/dev/null 2>&1; then
  mkdir -p "$TEST_ROOT/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/bin/chown"
  chmod +x "$TEST_ROOT/bin/chown"
  TEST_PATH="$TEST_ROOT/bin:$PATH"
fi

BEDROCK_ROOT="$TEST_ROOT" PATH="$TEST_PATH" NO_COLOR=1 bash "$ROOT/scripts/engine-manager.sh" prepare >/dev/null

check_instance(){
  local instance="$1" port="$2" level="$3" label="$4"
  local yaml="$TEST_ROOT/instances/$instance/pnx.yml"
  local props="$TEST_ROOT/instances/$instance/server.properties"
  [[ -f "$yaml" && -f "$props" ]]
  grep -Fxq "  port: $port" "$yaml"
  grep -Fxq "  defaultLevelName: \"$level\"" "$yaml"
  grep -Fxq "server-port=$port" "$props"
  grep -Fxq "level-name=$level" "$props"
  grep -Fxq "server-name=Nexora Network | $label" "$props"
  grep -Fxq "  motd: \"Nexora Network | $label\"" "$yaml"
  grep -Fxq '  sub-motd: "Survival, PvP, BedWars y SkyWars en una sola aventura"' "$yaml"
}

check_instance pvp 19134 PvP PvP
# `world` is intentional here: the pinned SilentBedwars fallback opens that
# level explicitly, so the managed BedWars instance preserves compatibility.
check_instance bedwars 19135 world BedWars
check_instance skywars 19136 SkyWars SkyWars

# No managed PNX minigame may ever inherit the Lobby UDP port.
! grep -R -Fxq '  port: 19132' "$TEST_ROOT/instances/pvp/pnx.yml" "$TEST_ROOT/instances/bedwars/pnx.yml" "$TEST_ROOT/instances/skywars/pnx.yml"

echo "Managed PowerNukkitX port/level regression passed."
