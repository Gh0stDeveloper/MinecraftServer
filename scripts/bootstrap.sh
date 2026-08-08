#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta como root: sudo $0" >&2
  exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" ]]; then
  echo "ERROR: BDS Linux oficial requiere x86_64/AMD64. Arquitectura detectada: $ARCH" >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y unzip rsync curl jq ufw ca-certificates tar

if ! id bedrock >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/bedrock-network --shell /usr/sbin/nologin bedrock
fi

mkdir -p /opt/bedrock-network/{instances,backups,scripts,addons,config}
chown -R bedrock:bedrock /opt/bedrock-network

echo "Bootstrap completado para $ARCH."
