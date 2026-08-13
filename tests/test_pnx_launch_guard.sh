#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/nexora-pnx-launch.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/instances/bedwars" "$TEST_ROOT/pnx/current" "$TEST_ROOT/config" "$TEST_ROOT/bin"
touch "$TEST_ROOT/pnx/current/powernukkitx-shaded.jar"
cp "$ROOT/config/engines.env" "$TEST_ROOT/config/engines.env"
cp "$ROOT/config/network.env" "$TEST_ROOT/config/network.env"
cp "$ROOT/instances/bedwars/server.properties" "$TEST_ROOT/instances/bedwars/server.properties"
printf 'legacy: true\n' > "$TEST_ROOT/instances/bedwars/nukkit.yml"
printf 'settings:\n  ip: 0.0.0.0\n  port: 19132\nconfig:\n  version: "3.0.0"\n' > "$TEST_ROOT/instances/bedwars/pnx.yml"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/bin/java"
chmod +x "$TEST_ROOT/bin/java"

set +e
output="$(BEDROCK_ROOT="$TEST_ROOT" PATH="$TEST_ROOT/bin:$PATH" NO_COLOR=1 bash "$ROOT/scripts/launch-instance.sh" bedwars 2>&1)"
rc=$?
set -e

[[ "$rc" -ne 0 ]]
[[ ! -e "$TEST_ROOT/instances/bedwars/nukkit.yml" ]]
grep -Fxq '  port: 19135' "$TEST_ROOT/instances/bedwars/pnx.yml"
grep -q 'PowerNukkitX terminó inesperadamente con código 0' <<<"$output"

echo "PowerNukkitX launch guard regression passed."
