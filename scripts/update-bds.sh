#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
lock_manager
source_engines
validate_engine_layout
requested="latest"; rollback=""
[[ "${1:-}" == "--yes" ]] && shift
if [[ "${1:-}" == "--rollback" ]]; then rollback="${2:-}"; shift 2 || true; else requested="${1:-latest}"; fi
mkdir -p "$RELEASES_DIR" "$CACHE_DIR" "$STATE_DIR"
apply_release(){
  local version="$1" release="$RELEASES_DIR/$1" instance target
  [[ -x "$release/bedrock_server" ]] || die "BDS $version no está descargado."
  while IFS= read -r instance; do
    [[ -n "$instance" ]] || continue
    target="$INSTANCES_DIR/$instance"; mkdir -p "$target"
    rsync -a "$release/" "$target/" --exclude='server.properties' --exclude='allowlist.json' --exclude='permissions.json' --exclude='worlds/' --exclude='behavior_packs/' --exclude='resource_packs/' --exclude='development_behavior_packs/' --exclude='development_resource_packs/' --exclude='plugins/' --exclude='pnx.yml'
    [[ -d "$release/behavior_packs" ]] && rsync -a "$release/behavior_packs/" "$target/behavior_packs/"
    [[ -d "$release/resource_packs" ]] && rsync -a "$release/resource_packs/" "$target/resource_packs/"
    chmod +x "$target/bedrock_server"
  done < <(instances_by_engine bds)
  chown -R bedrock:bedrock "$INSTANCES_DIR"
}
activate_release(){
  local version="$1"
  apply_release "$version"
  ln -sfn "$RELEASES_DIR/$version" "$CURRENT_LINK.new"; mv -Tf "$CURRENT_LINK.new" "$CURRENT_LINK"
  printf '%s\n' "$version" > "$STATE_DIR/bds-version"; chown bedrock:bedrock "$STATE_DIR/bds-version"
}
download_release(){
  local meta version url target zip tmp expected_sha1 expected_size
  local -a downloader_args
  meta="$(python3 "$APP_DIR/scripts/bds-resolver.py" --version "$requested")" || die "No se pudo resolver la versión BDS."
  version="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["version"])' "$meta")"
  url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["url"])' "$meta")"
  expected_sha1="$(python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get("sha1"); print(v or "")' "$meta")"
  expected_size="$(python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get("size_in_bytes"); print(v or "")' "$meta")"
  target="$RELEASES_DIR/$version"
  if [[ ! -x "$target/bedrock_server" ]]; then
    log "Descargando BDS $version desde el CDN oficial de Minecraft..." >&2
    zip="$CACHE_DIR/bedrock-server-$version.zip"
    downloader_args=(--url "$url" --output "$zip" --attempts 5 --timeout 45)
    [[ -n "$expected_sha1" ]] && downloader_args+=(--sha1 "$expected_sha1")
    [[ -n "$expected_size" ]] && downloader_args+=(--size "$expected_size")
    if ! python3 "$APP_DIR/scripts/bds-downloader.py" "${downloader_args[@]}" >/dev/null; then
      rm -f "$zip" "$zip.part"
      die "No se pudo obtener un ZIP BDS íntegro para $version."
    fi
    tmp="$(mktemp -d "$RELEASES_DIR/.extract-XXXXXX")"
    if ! unzip -q "$zip" -d "$tmp"; then
      rm -rf "$tmp"; rm -f "$zip"
      die "No se pudo extraer el ZIP BDS validado."
    fi
    [[ -f "$tmp/bedrock_server" ]] || { rm -rf "$tmp"; rm -f "$zip"; die "ZIP BDS inválido: falta bedrock_server."; }
    chmod +x "$tmp/bedrock_server"
    rm -rf "$target"; mv "$tmp" "$target"; chown -R bedrock:bedrock "$target"
  fi
  printf '%s' "$version"
}
old="$(current_bds_version)"; was_active="$(active_instances)"
if [[ -n "$rollback" ]]; then
  [[ -d "$RELEASES_DIR/$rollback" ]] || die "Versión no instalada: $rollback"
  stop_network; "$APP_DIR/scripts/network-backup.sh" --online-stopped >/dev/null; activate_release "$rollback"; start_instance_list "$was_active"
  instances_healthy "$was_active" || { stop_network; [[ "$old" != none ]] && activate_release "$old"; start_instance_list "$was_active"; die "Rollback falló."; }
  ok "BDS cambiado de $old a $rollback. Los mundos no se sustituyeron."; exit 0
fi
new="$(download_release)"
if [[ "$old" == "$new" ]]; then apply_release "$new"; ok "BDS ya está actualizado ($new); runtime BDS sincronizado."; exit 0; fi
log "Actualizando BDS: $old -> $new"; stop_network; backup="$("$APP_DIR/scripts/network-backup.sh" --online-stopped | tail -n1)"; assert_survival_safe; activate_release "$new"; start_instance_list "$was_active"
if ! instances_healthy "$was_active"; then
  warn "La nueva versión no inició correctamente."; if [[ "$old" != none && -d "$RELEASES_DIR/$old" ]]; then stop_network; activate_release "$old"; start_instance_list "$was_active"; fi
  die "Actualización revertida. Backup: $backup"
fi
ok "BDS actualizado a $new. Backup: $backup"
