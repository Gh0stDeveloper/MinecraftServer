#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Los scripts de instalación deben seguir rechazando ejecuciones sin root. En
# CI se prueba esa misma ruta elevando únicamente este test; los runners de
# GitHub ofrecen sudo sin contraseña. No se añade ningún bypass al código que
# se ejecuta en producción.
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || {
    echo "test_configure_instances.sh requiere root o sudo sin contraseña" >&2
    exit 1
  }
  exec sudo -n bash "$0" "$@"
fi

TEST_ROOT="$(mktemp -d /tmp/nexora-instance-migration.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/instances/lobby" "$TEST_ROOT/instances/survival"
cp "$ROOT/instances/lobby/server.properties" "$TEST_ROOT/instances/lobby/server.properties"
cp "$ROOT/instances/survival/server.properties" "$TEST_ROOT/instances/survival/server.properties"
printf '[]\n' > "$TEST_ROOT/instances/survival/allowlist.json"
printf '%s\n' \
  'SERVER_NAME="Bedrock Network"' \
  'PUBLIC_IP="203.0.113.10"' \
  'PUBLIC_DOMAIN=""' \
  'PUBLIC_HOST="203.0.113.10"' \
  'LOBBY_PORT=19132' \
  'SURVIVAL_PORT=19133' \
  'PVP_PORT=19134' \
  'BEDWARS_PORT=19135' \
  'SKYWARS_PORT=19136' \
  > "$TEST_ROOT/config/network.env"

sed -i 's/^server-port=.*/server-port=19132/' "$TEST_ROOT/instances/lobby/server.properties"
sed -i 's/^server-port=.*/server-port=19133/' "$TEST_ROOT/instances/survival/server.properties"
sed -i 's/^allow-list=.*/allow-list=true/' "$TEST_ROOT/instances/survival/server.properties"

BEDROCK_ROOT="$TEST_ROOT" NO_COLOR=1 bash "$ROOT/scripts/configure-instances.sh" >/dev/null

grep -Fxq 'SERVER_NAME="Nexora Network"' "$TEST_ROOT/config/network.env"
grep -q '^SERVER_DESCRIPTION=' "$TEST_ROOT/config/network.env"
grep -Fxq 'TRANSFER_HOST_MODE="ip"' "$TEST_ROOT/config/network.env"
grep -Fxq 'LOBBY_BACKEND_PORT="20132"' "$TEST_ROOT/config/network.env"
grep -Fxq 'SURVIVAL_BACKEND_PORT="20133"' "$TEST_ROOT/config/network.env"
grep -Fxq 'server-port=20132' "$TEST_ROOT/instances/lobby/server.properties"
grep -Fxq 'server-port=20133' "$TEST_ROOT/instances/survival/server.properties"
grep -Fxq 'allow-list=false' "$TEST_ROOT/instances/survival/server.properties"

# Una lista realmente configurada por el administrador debe sobrevivir a las
# actualizaciones, porque no está relacionada con el estado de los logros.
printf '[{"name":"NexoraAdmin","ignoresPlayerLimit":false}]\n' > "$TEST_ROOT/instances/survival/allowlist.json"
sed -i 's/^allow-list=.*/allow-list=true/' "$TEST_ROOT/instances/survival/server.properties"
sed -i 's/^SERVER_NAME=.*/SERVER_NAME="Mi Reino"/' "$TEST_ROOT/config/network.env"
BEDROCK_ROOT="$TEST_ROOT" NO_COLOR=1 bash "$ROOT/scripts/configure-instances.sh" >/dev/null
grep -Fxq 'allow-list=true' "$TEST_ROOT/instances/survival/server.properties"
grep -Fxq 'SERVER_NAME="Mi Reino"' "$TEST_ROOT/config/network.env"
grep -Fxq 'server-name=Mi Reino | Lobby' "$TEST_ROOT/instances/lobby/server.properties"
grep -Fxq 'server-name=Mi Reino | Survival' "$TEST_ROOT/instances/survival/server.properties"

echo "BDS public/backend port migration regression passed."
