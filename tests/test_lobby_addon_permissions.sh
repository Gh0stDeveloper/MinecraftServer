#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/nexora-addon-test.XXXXXX)"
trap 'sudo rm -rf "$TMP"' EXIT

sudo groupadd -f bedrock
id bedrock >/dev/null 2>&1 || sudo useradd --system --gid bedrock --no-create-home --shell /usr/sbin/nologin bedrock
sudo mkdir -p "$TMP/instances/lobby/worlds/Lobby"
sudo cp "$ROOT/instances/lobby/server.properties" "$TMP/instances/lobby/server.properties"
sudo BEDROCK_ROOT="$TMP" bash "$ROOT/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp" >/dev/null

python3 - "$TMP" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
module_uuid='7cba643d-0a55-4f76-9046-c17097b1b2c9'
expected={'@minecraft/server','@minecraft/server-ui'}
for path in [
    root/'instances/lobby/config/default/permissions.json',
    root/'instances/lobby/config'/module_uuid/'permissions.json',
]:
    data=json.loads(path.read_text())
    assert expected <= set(data.get('allowed_modules', [])), (path, data)
world=json.loads((root/'instances/lobby/worlds/Lobby/world_behavior_packs.json').read_text())
assert any(x.get('pack_id')=='f74dd021-40ac-4f37-a5aa-3a78f12520ff' for x in world)
print('Lobby addon permissions regression passed.')
PY
