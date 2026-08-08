#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
backup_network(){
  local stamp out instance target item
  stamp="$(date +%Y%m%d-%H%M%S)"; out="$BACKUP_DIR/network-$stamp"; mkdir -p "$out"
  log "Backup consistente: $out" >&2
  for instance in "${INSTANCES[@]}"; do
    target="$INSTANCES_DIR/$instance"; [[ -d "$target" ]] || continue
    local -a keep=()
    for item in server.properties allowlist.json permissions.json worlds behavior_packs resource_packs development_behavior_packs development_resource_packs plugins pnx.yml players; do [[ -e "$target/$item" ]] && keep+=("$item"); done
    ((${#keep[@]})) && tar -C "$target" -czf "$out/$instance.tar.gz" "${keep[@]}"
  done
  [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$out/network.env"
  [[ -f "$ENGINES_FILE" ]] && cp "$ENGINES_FILE" "$out/engines.env"
  printf '%s\n' "$(current_bds_version)" > "$out/bds-version"
  printf '%s\n' "$(current_pnx_version)" > "$out/pnx-version"
  chown -R bedrock:bedrock "$out"
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'network-*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | tail -n +11 | cut -d' ' -f2- | xargs -r rm -rf
  printf '%s\n' "$out"
}
if [[ "${1:-}" == "--online-stopped" ]]; then backup_network; else lock_manager; stop_network; out="$(backup_network | tail -n1)"; start_network; ok "Backup creado: $out"; fi
