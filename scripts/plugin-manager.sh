#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
source_engines
CATALOG="$APP_DIR/config/plugins.json"
PLUGIN_STATE="$STATE_DIR/plugins"
BUILD_ROOT="$ROOT/plugin-build"
mkdir -p "$PLUGIN_STATE" "$BUILD_ROOT"
usage(){ cat <<'HELP'
Uso:
  mcserver plugins list
  mcserver plugins sync
  mcserver plugins install <id>
  mcserver plugins doctor

Los plugins se compilan desde fuentes fijadas en config/plugins.json.
No se redistribuyen binarios de terceros dentro de este repositorio.
HELP
}
need_tools(){ command -v jq >/dev/null || die "Falta jq."; command -v git >/dev/null || die "Falta git."; command -v java >/dev/null || die "Falta Java."; }
row(){ local id="$1"; jq -cer --arg id "$id" '.plugins[] | select(.id == $id)' "$CATALOG"; }
target_jar(){ local item="$1" id instance; id="$(jq -r '.id' <<<"$item")"; instance="$(jq -r '.instance' <<<"$item")"; printf '%s/%s/plugins/%s.jar' "$INSTANCES_DIR" "$instance" "$id"; }
render_internal_config(){
  local id="$1" instance="$2"
  [[ "$id" == nexora-practice ]] || return 0
  mkdir -p "$INSTANCES_DIR/$instance/plugins/NexoraPractice"
  cat > "$INSTANCES_DIR/$instance/plugins/NexoraPractice/config.yml" <<EOF2
lobby-host: "${PUBLIC_HOST}"
lobby-port: ${LOBBY_PORT}
EOF2
}
build_local_maven(){
  local item="$1" src artifact
  src="$APP_DIR/$(jq -r '.source' <<<"$item")"; artifact="$(jq -r '.artifact' <<<"$item")"
  [[ -f "$src/pom.xml" ]] || die "Proyecto Maven inexistente: $src"
  (cd "$src" && mvn -q -DskipTests package)
  [[ -f "$src/$artifact" ]] || die "No se creó $src/$artifact"
  printf '%s' "$src/$artifact"
}
build_git_gradle(){
  local item="$1" id repo ref task glob dir artifact
  id="$(jq -r '.id' <<<"$item")"; repo="$(jq -r '.source' <<<"$item")"; ref="$(jq -r '.ref' <<<"$item")"; task="$(jq -r '.build' <<<"$item")"; glob="$(jq -r '.artifact_glob' <<<"$item")"; dir="$BUILD_ROOT/$id"
  rm -rf "$dir"; git clone -q --filter=blob:none "$repo" "$dir"; (cd "$dir" && git checkout -q --detach "$ref")
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$ref" ]] || die "$id no quedó fijado en $ref"
  chmod +x "$dir/gradlew"; (cd "$dir" && ./gradlew --no-daemon --console=plain clean "$task")
  artifact="$(find "$dir" -path "$dir/$glob" -type f -name '*.jar' | head -n1)"
  [[ -n "$artifact" && -f "$artifact" ]] || die "No se encontró artefacto de $id ($glob)"
  printf '%s' "$artifact"
}
install_one(){
  local id="$1" item instance engine src_type expected target artifact actual_ref
  item="$(row "$id")" || die "Plugin desconocido: $id"; instance="$(jq -r '.instance' <<<"$item")"; engine="$(engine_for "$instance")"
  [[ "$engine" == pnx ]] || { warn "$id omitido: $instance usa $engine."; return 0; }
  src_type="$(jq -r '.source_type' <<<"$item")"; expected="$(jq -r '.minecraft' <<<"$item")"
  [[ "$expected" == "$PNX_EXPECTED_MINECRAFT" ]] || die "$id está catalogado para Bedrock $expected, no $PNX_EXPECTED_MINECRAFT."
  case "$src_type" in
    local-maven) artifact="$(build_local_maven "$item")"; actual_ref="$(jq -r '.version' <<<"$item")";;
    git-gradle) artifact="$(build_git_gradle "$item")"; actual_ref="$(jq -r '.ref' <<<"$item")";;
    *) die "source_type no soportado para $id: $src_type";;
  esac
  target="$(target_jar "$item")"; mkdir -p "$(dirname "$target")"; install -m 0644 "$artifact" "$target.tmp"; mv -f "$target.tmp" "$target"
  printf '%s\n' "$actual_ref" > "$PLUGIN_STATE/$id.ref"; sha256sum "$target" | awk '{print $1}' > "$PLUGIN_STATE/$id.sha256"
  render_internal_config "$id" "$instance"; chown -R bedrock:bedrock "$INSTANCES_DIR/$instance/plugins" "$PLUGIN_STATE"; ok "$id instalado en $instance."
}
sync_plugins(){
  need_tools
  local id auto item target wanted installed failures=0
  while IFS= read -r id; do
    item="$(row "$id")"; auto="$(jq -r '.auto_install' <<<"$item")"; [[ "$auto" == true ]] || continue
    [[ "$(engine_for "$(jq -r '.instance' <<<"$item")")" == pnx ]] || continue
    target="$(target_jar "$item")"
    if [[ "$(jq -r '.source_type' <<<"$item")" == local-maven ]]; then wanted="$(jq -r '.version' <<<"$item")"; else wanted="$(jq -r '.ref' <<<"$item")"; fi
    installed="$(cat "$PLUGIN_STATE/$id.ref" 2>/dev/null || true)"
    if [[ ! -f "$target" || "$installed" != "$wanted" ]]; then install_one "$id" || failures=$((failures+1)); else render_internal_config "$id" "$(jq -r '.instance' <<<"$item")"; ok "$id ya está fijado en $wanted."; fi
  done < <(jq -r '.plugins[].id' "$CATALOG")
  ((failures == 0)) || die "Fallaron $failures plugin(s)."
}
doctor(){
  local id item instance target wanted installed fail=0
  while IFS= read -r id; do
    item="$(row "$id")"; instance="$(jq -r '.instance' <<<"$item")"; [[ "$(engine_for "$instance")" == pnx ]] || continue
    target="$(target_jar "$item")"; if [[ "$(jq -r '.source_type' <<<"$item")" == local-maven ]]; then wanted="$(jq -r '.version' <<<"$item")"; else wanted="$(jq -r '.ref' <<<"$item")"; fi
    installed="$(cat "$PLUGIN_STATE/$id.ref" 2>/dev/null || true)"
    if [[ -f "$target" && "$installed" == "$wanted" ]]; then ok "$id: instalado ($instance)"; else warn "$id: faltante o desactualizado en $instance (esperado $wanted)."; fail=$((fail+1)); fi
  done < <(jq -r '.plugins[].id' "$CATALOG")
  return "$fail"
}
list_plugins(){
  printf '\n%-18s %-10s %-9s %-16s %s\n' PLUGIN INSTANCIA AUTO LICENCIA REF
  printf '%-18s %-10s %-9s %-16s %s\n' '------' '---------' '----' '--------' '---'
  jq -r '.plugins[] | [.id,.instance,(.auto_install|tostring),.license,(.ref // .version)] | @tsv' "$CATALOG" | while IFS=$'\t' read -r a b c d e; do printf '%-18s %-10s %-9s %-16s %s\n' "$a" "$b" "$c" "$d" "$e"; done
}
case "${1:-list}" in
  list) list_plugins;;
  sync) sync_plugins;;
  install) [[ $# -eq 2 ]] || { usage; exit 1; }; need_tools; install_one "$2";;
  doctor) doctor;;
  *) usage; exit 1;;
esac
