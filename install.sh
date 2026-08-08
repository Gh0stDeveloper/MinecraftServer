#!/usr/bin/env bash
set -Eeuo pipefail
URL="https://github.com/Gh0stDeveloper/MinecraftServer/archive/refs/heads/main.tar.gz"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '[installer] Descargando MinecraftServer...\n'
curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$TMP/project.tar.gz"
tar -xzf "$TMP/project.tar.gz" -C "$TMP"
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 'MinecraftServer-*' | head -n1)"
[[ -n "$SRC" ]] || { echo 'No se pudo extraer el proyecto.' >&2; exit 1; }
chmod +x "$SRC/mcserver" "$SRC/scripts"/*.sh
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then exec "$SRC/mcserver" install "$@"; else exec sudo "$SRC/mcserver" install "$@"; fi
