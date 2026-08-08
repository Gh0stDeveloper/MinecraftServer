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

PNX_SOURCE_REPO="${PNX_SOURCE_REPO:-https://github.com/PowerNukkitX/PowerNukkitX.git}"
PNX_SOURCE_REF="${PNX_SOURCE_REF:-e9d4ffaa5638ca0f82bcdedf3320afd6cf92e38d}"
PNX_EXPECTED_VERSION="${PNX_EXPECTED_VERSION:-3.0.2}"

activate_release(){
  local release="$1"
  [[ -f "$PNX_RELEASES_DIR/$release/powernukkitx-shaded.jar" ]] || die "Release PNX no instalada: $release"
  ln -sfn "$PNX_RELEASES_DIR/$release" "$PNX_CURRENT_LINK.new"
  mv -Tf "$PNX_CURRENT_LINK.new" "$PNX_CURRENT_LINK"
  printf '%s\n' "$release" > "$STATE_DIR/pnx-version"
  sha256sum "$PNX_RELEASES_DIR/$release/powernukkitx-shaded.jar" | awk '{print $1}' > "$STATE_DIR/pnx-sha256"
  chown -R bedrock:bedrock "$PNX_DIR" "$STATE_DIR/pnx-version" "$STATE_DIR/pnx-sha256"
}

validate_pnx_jar(){
  local jar_file="$1"
  [[ -s "$jar_file" ]] || return 1
  jar tf "$jar_file" 2>/dev/null | grep -Fxq 'org/powernukkitx/JarStart.class'
}

build_pnx_from_source(){
  local output="$1" src actual_ref src_version src_mc built
  command -v git >/dev/null 2>&1 || die "Se requiere git para construir PowerNukkitX desde código fuente."
  command -v java >/dev/null 2>&1 || die "Se requiere Java ${PNX_JAVA_MIN}+ para PowerNukkitX."
  src="$(mktemp -d "$CACHE_DIR/pnx-source.XXXXXX")"
  log "El snapshot publicado no está disponible; construyendo PowerNukkitX desde el commit oficial fijado ${PNX_SOURCE_REF:0:12}..."
  git -C "$src" init -q
  git -C "$src" remote add origin "$PNX_SOURCE_REPO"
  git -C "$src" fetch -q --depth 1 origin "$PNX_SOURCE_REF"
  git -C "$src" checkout -q --detach FETCH_HEAD
  actual_ref="$(git -C "$src" rev-parse HEAD)"
  [[ "$actual_ref" == "$PNX_SOURCE_REF" ]] || { rm -rf "$src"; die "El commit PNX descargado no coincide con el pin configurado."; }

  src_version="$(sed -n 's/.*badge\/version-\([0-9][0-9.]*\)-blue.*/\1/p' "$src/README.md" | head -n1)"
  src_mc="$(sed -n 's/.*minecraft-v\([^% ]*\)%20(Bedrock).*/\1/p' "$src/README.md" | head -n1)"
  [[ "$src_version" == "$PNX_EXPECTED_VERSION" ]] || { rm -rf "$src"; die "El commit PNX fijado anuncia versión ${src_version:-desconocida}, esperada $PNX_EXPECTED_VERSION."; }
  [[ "$src_mc" == "$PNX_EXPECTED_MINECRAFT" ]] || { rm -rf "$src"; die "El commit PNX fijado anuncia Bedrock ${src_mc:-desconocido}, esperado $PNX_EXPECTED_MINECRAFT."; }

  chmod +x "$src/gradlew"
  (
    cd "$src"
    ./gradlew \
      --no-daemon \
      --console=plain \
      --no-configuration-cache \
      --max-workers=1 \
      -Dorg.gradle.parallel=false \
      -Dorg.gradle.jvmargs='-Xmx1536m -Xms256m -Dfile.encoding=UTF-8 -XX:+UseG1GC' \
      -PbuildVersion="$PNX_EXPECTED_VERSION" \
      shadowJar
  )
  built="$src/build/powernukkitx.jar"
  [[ -f "$built" ]] || { rm -rf "$src"; die "El build oficial PNX terminó sin generar build/powernukkitx.jar."; }
  validate_pnx_jar "$built" || { rm -rf "$src"; die "El shaded JAR construido no contiene org.powernukkitx.JarStart."; }
  install -m 0644 "$built" "$output"
  rm -rf "$src"
  ok "PowerNukkitX $PNX_EXPECTED_VERSION construido desde el commit oficial ${PNX_SOURCE_REF:0:12}."
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

meta_url="https://raw.githubusercontent.com/PowerNukkitX/PowerNukkitX/$PNX_SOURCE_REF/README.md"
meta="$(curl --http1.1 -fsSL --retry 3 --connect-timeout 15 "$meta_url" || true)"
version="$(printf '%s' "$meta" | sed -n 's/.*badge\/version-\([0-9][0-9.]*\)-blue.*/\1/p' | head -n1)"
mc_version="$(printf '%s' "$meta" | sed -n 's/.*minecraft-v\([^% ]*\)%20(Bedrock).*/\1/p' | head -n1)"
version="${version:-$PNX_EXPECTED_VERSION}"
[[ "$version" == "$PNX_EXPECTED_VERSION" ]] || die "El metadata PNX fijado anuncia $version, esperado $PNX_EXPECTED_VERSION."
[[ -z "$mc_version" || "$mc_version" == "$PNX_EXPECTED_MINECRAFT" ]] || die "PowerNukkitX fijado anuncia Bedrock $mc_version, esperado $PNX_EXPECTED_MINECRAFT."
log "PowerNukkitX $version compatible con Bedrock $PNX_EXPECTED_MINECRAFT."

host="$(python3 - "$PNX_DOWNLOAD_URL" <<'PY'
from urllib.parse import urlparse
import sys
print((urlparse(sys.argv[1]).hostname or '').lower())
PY
)"
[[ "$host" == github.com || "$host" == objects.githubusercontent.com || "$host" == githubusercontent.com ]] || die "Origen PNX no permitido: $host"

tmp="$(mktemp "$CACHE_DIR/pnx.XXXXXX.jar")"
trap 'rm -f "$tmp"' EXIT
source_kind="snapshot"
log "Intentando snapshot oficial publicado por PowerNukkitX..."
if ! curl --http1.1 -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 300 "$PNX_DOWNLOAD_URL" -o "$tmp"; then
  warn "El asset snapshot oficial no está disponible. Activando fallback reproducible desde código fuente."
  rm -f "$tmp"
  tmp="$(mktemp "$CACHE_DIR/pnx.XXXXXX.jar")"
  build_pnx_from_source "$tmp"
  source_kind="source-${PNX_SOURCE_REF:0:12}"
fi

validate_pnx_jar "$tmp" || die "El JAR PNX obtenido no es un servidor ejecutable válido."
sha="$(sha256sum "$tmp" | awk '{print $1}')"
old_sha="$(cat "$STATE_DIR/pnx-sha256" 2>/dev/null || true)"
if [[ "$sha" == "$old_sha" && "$old" != none ]]; then
  ok "PowerNukkitX ya está actualizado ($old)."
  exit 0
fi

release="${version}-${source_kind}-${sha:0:12}"
target="$PNX_RELEASES_DIR/$release"
mkdir -p "$target"
install -m 0644 "$tmp" "$target/powernukkitx-shaded.jar"
printf '%s\n' "$PNX_SOURCE_REF" > "$target/upstream-commit"
printf '%s\n' "$source_kind" > "$target/source-kind"
chown -R bedrock:bedrock "$target"
stop_network
backup="$("$APP_DIR/scripts/network-backup.sh" --online-stopped | tail -n1)"
activate_release "$release"
start_instance_list "$was_active"
if ! instances_healthy "$was_active"; then
  warn "El nuevo PNX no inició correctamente."
  if [[ "$old" != none && -d "$PNX_RELEASES_DIR/$old" ]]; then
    stop_network
    activate_release "$old"
    start_instance_list "$was_active"
  fi
  die "Actualización PNX revertida. Backup: $backup"
fi
ok "PowerNukkitX actualizado a $release. Backup: $backup"
