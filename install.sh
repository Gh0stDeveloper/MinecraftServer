#!/usr/bin/env bash
set -Eeuo pipefail
URL="https://github.com/Gh0stDeveloper/MinecraftServer/archive/refs/heads/main.tar.gz"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  R=$'\033[0m'; B=$'\033[1m'; C=$'\033[38;5;45m'; V=$'\033[38;5;141m'; P=$'\033[38;5;213m'; W=$'\033[97m'
else
  R="" B="" C="" V="" P="" W=""
fi
printf '\n%b╭────────────────────────────────────────────────────────╮%b\n' "$V$B" "$R"
printf '%b│%b  %bNEXORA · BEDROCK NETWORK%b%-29s%b│%b\n' "$V$B" "$R" "$W$B" "$R" "" "$V$B" "$R"
printf '%b│%b  %-54s%b│%b\n' "$V$B" "$R" 'Instalador público para Ubuntu 22.04 / 24.04 AMD64' "$V$B" "$R"
printf '%b╰────────────────────────────────────────────────────────╯%b\n\n' "$V$B" "$R"
printf '%b[◆]%b %bDescargando el instalador más reciente...%b\n' "$C$B" "$R" "$B" "$R"
curl -fsSL --retry 3 --connect-timeout 15 "$URL" -o "$TMP/project.tar.gz"
tar -xzf "$TMP/project.tar.gz" -C "$TMP"
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 'MinecraftServer-*' | head -n1)"
[[ -n "$SRC" ]] || { printf '%b[×]%b No se pudo extraer el proyecto.\n' "$P$B" "$R" >&2; exit 1; }
chmod +x "$SRC/mcserver" "$SRC/install.sh" "$SRC/scripts"/*.sh
printf '%b[✓]%b %bProyecto preparado; iniciando asistente.%b\n' "$V$B" "$R" "$B" "$R"
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then exec "$SRC/mcserver" install "$@"; else exec sudo "$SRC/mcserver" install "$@"; fi
