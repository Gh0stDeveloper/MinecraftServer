#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
lock_manager
source_engines
validate_engine_layout
mkdir -p "$PNX_RELEASES_DIR" "$CACHE_DIR" "$STATE_DIR"
rollback=""
[[ "${1:-}" == "--rollback" ]] && { rollback="${2:-}"; [[ -n "$rollback" ]] || die "Falta release PNX."; }
activate_release(){
  local release="$1"
  [[ -f "$PNX_RELEASES_DIR/$release/powernukkitx-shaded.jar" ]] || die "Release PNX no instalada: $release"
  ln -sfn "$PNX_RELEASES_DIR/$release" "$PNX_CURRENT_LINK.new"
  mv -Tf "$PNX_CURRENT_LINK.new" "$PNX_CURRENT_LINK"
  printf '%s\n' "$release" > "$STATE_DIR/pnx-version"
  sha256sum "$PNX_RELEASES_DIR/$release/powernukkitx-shaded.jar" | awk '{print $1}' > "$STATE_DIR/pnx-sha256"
  chown -R bedrock:bedrock "$PNX_DIR" "$STATE_DIR/pnx-version" "$STATE_DIR/pnx-sha256"
}
old="$(current_pnx_version)"
was_active="$(active_instances)"
if [[ -n "$rollback" ]]; then
  [[ -d "$PNX_RELEASES_DIR/$rollback" ]] || die "Release PNX no instalada: $rollback"
  stop_network
  backup="$("$APP_DIR/scripts/network-backup.sh" --online-stopped | tail -n1)"
  activate_release "$rollback"
  start_instance_list "$was_active"
  instances_healthy "$was_active" || die "El rollback PNX no dejó la red saludable. Backup: $backup"
  ok "PNX cambiado a $rollback. Backup: $backup"
  exit 0
fi
meta="$(curl --http1.1 -fsSL --retry 5 --retry-all-errors --connect-timeout 15 https://raw.githubusercontent.com/PowerNukkitX/PowerNukkitX/master/README.md || true)"
version="$(printf '%s' "$meta" | sed -n 's/.*badge\/version-\([0-9][0-9.]*\)-blue.*/\1/p' | head -n1)"
mc_version="$(printf '%s' "$meta" | sed -n 's/.*minecraft-v\([^% ]*\)%20(Bedrock).*/\1/p' | head -n1)"
version="${version:-snapshot}"
[[ -n "$mc_version" ]] && log "PowerNukkitX $version anuncia soporte Bedrock $mc_version."
host="$(python3 - "$PNX_DOWNLOAD_URL" <<'PY'
from urllib.parse import urlparse
import sys
print((urlparse(sys.argv[1]).hostname or '').lower())
PY
)"
[[ "$host" == github.com || "$host" == objects.githubusercontent.com || "$host" == githubusercontent.com ]] || die "Origen PNX no permitido: $host"
tmp="$(mktemp "$CACHE_DIR/pnx.XXXXXX.jar")"
trap 'rm -f "$tmp"' EXIT
log "Descargando PowerNukkitX desde el release snapshot oficial..."
curl --http1.1 -fL --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 "$PNX_DOWNLOAD_URL" -o "$tmp"
[[ -s "$tmp" ]] || die "Descarga PNX vacía."
sha="$(sha256sum "$tmp" | awk '{print $1}')"
old_sha="$(cat "$STATE_DIR/pnx-sha256" 2>/dev/null || true)"
if [[ "$sha" == "$old_sha" && "$old" != none ]]; then ok "PowerNukkitX ya está actualizado ($old)."; exit 0; fi
release="${version}-${sha:0:12}"
target="$PNX_RELEASES_DIR/$release"
mkdir -p "$target"
install -m 0644 "$tmp" "$target/powernukkitx-shaded.jar"
chown -R bedrock:bedrock "$target"
stop_network
backup="$("$APP_DIR/scripts/network-backup.sh" --online-stopped | tail -n1)"
activate_release "$release"
start_instance_list "$was_active"
if ! instances_healthy "$was_active"; then
  warn "El nuevo PNX no inició correctamente."
  if [[ "$old" != none && -d "$PNX_RELEASES_DIR/$old" ]]; then stop_network; activate_release "$old"; start_instance_list "$was_active"; fi
  die "Actualización PNX revertida. Backup: $backup"
fi
ok "PowerNukkitX actualizado a $release. Backup: $backup"
