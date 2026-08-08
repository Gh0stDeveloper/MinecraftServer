#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
source_engines
CATALOG="$APP_DIR/config/plugins.json"
GRADLE_COMPAT="$APP_DIR/config/pnx-gradle.init.gradle"
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
Los plugins con auto_install=false son fallbacks manuales y no bloquean doctor.
HELP
}
need_tools(){ command -v jq >/dev/null || die "Falta jq."; command -v git >/dev/null || die "Falta git."; command -v java >/dev/null || die "Falta Java."; command -v mvn >/dev/null || die "Falta Maven."; }
row(){ local id="$1"; jq -cer --arg id "$id" '.plugins[] | select(.id == $id)' "$CATALOG"; }
target_jar(){ local item="$1" id instance; id="$(jq -r '.id' <<<"$item")"; instance="$(jq -r '.instance' <<<"$item")"; printf '%s/%s/plugins/%s.jar' "$INSTANCES_DIR" "$instance" "$id"; }
render_internal_config(){
  local id="$1" instance="$2" folder cfg defaults plugin_folder
  case "$id" in
    nexora-practice) plugin_folder="NexoraPractice"; defaults="$APP_DIR/pnx-plugins/nexora-practice/src/main/resources/config.yml";;
    nexora-bedwars) plugin_folder="NexoraBedWars"; defaults="$APP_DIR/pnx-plugins/nexora-bedwars/src/main/resources/config.yml";;
    nexora-skywars) plugin_folder="NexoraSkyWars"; defaults="$APP_DIR/pnx-plugins/nexora-skywars/src/main/resources/config.yml";;
    *) return 0;;
  esac
  folder="$INSTANCES_DIR/$instance/plugins/$plugin_folder"; cfg="$folder/config.yml"; mkdir -p "$folder"; [[ -f "$cfg" ]] || cp "$defaults" "$cfg"
  if grep -q '^lobby-host:' "$cfg"; then sed -i "s|^lobby-host:.*|lobby-host: \"${PUBLIC_HOST}\"|" "$cfg"; else printf '\nlobby-host: "%s"\n' "$PUBLIC_HOST" >> "$cfg"; fi
  if grep -q '^lobby-port:' "$cfg"; then sed -i "s|^lobby-port:.*|lobby-port: ${LOBBY_PORT}|" "$cfg"; else printf 'lobby-port: %s\n' "$LOBBY_PORT" >> "$cfg"; fi
}
build_local_maven(){ local item="$1" src artifact; src="$APP_DIR/$(jq -r '.source' <<<"$item")"; artifact="$(jq -r '.artifact' <<<"$item")"; [[ -f "$src/pom.xml" ]] || die "Proyecto Maven inexistente: $src"; (cd "$src" && mvn -q -DskipTests package); [[ -f "$src/$artifact" ]] || die "No se creó $src/$artifact"; printf '%s' "$src/$artifact"; }
build_git_gradle(){
  local item="$1" id repo ref task glob dir artifact
  id="$(jq -r '.id' <<<"$item")"; repo="$(jq -r '.source' <<<"$item")"; ref="$(jq -r '.ref' <<<"$item")"; task="$(jq -r '.build' <<<"$item")"; glob="$(jq -r '.artifact_glob' <<<"$item")"; dir="$BUILD_ROOT/$id"
  [[ -f "$GRADLE_COMPAT" ]] || die "Falta $GRADLE_COMPAT"; rm -rf "$dir"; git clone -q --filter=blob:none "$repo" "$dir"; (cd "$dir" && git checkout -q --detach "$ref"); [[ "$(git -C "$dir" rev-parse HEAD)" == "$ref" ]] || die "$id no quedó fijado en $ref"
  chmod +x "$dir/gradlew"; (cd "$dir" && ./gradlew --no-daemon --console=plain --init-script "$GRADLE_COMPAT" clean "$task"); artifact="$(find "$dir" -path "$dir/$glob" -type f -name '*.jar' | head -n1)"; [[ -n "$artifact" && -f "$artifact" ]] || die "No se encontró artefacto de $id ($glob)"; printf '%s' "$artifact"
}
remove_conflicts(){
  local item="$1" instance conflict conflict_item target
  instance="$(jq -r '.instance' <<<"$item")"
  while IFS= read -r conflict; do
    [[ -n "$conflict" ]] || continue
    conflict_item="$(row "$conflict" 2>/dev/null || true)"; [[ -n "$conflict_item" ]] || continue
    target="$(target_jar "$conflict_item")"; rm -f "$target" "$PLUGIN_STATE/$conflict.ref" "$PLUGIN_STATE/$conflict.sha256"
    warn "Conflicto $conflict retirado de $instance."
  done < <(jq -r '.conflicts[]? // empty' <<<"$item")
}
install_one(){
  local id="$1" item instance engine src_type expected target artifact actual_ref
  item="$(row "$id")" || die "Plugin desconocido: $id"; instance="$(jq -r '.instance' <<<"$item")"; engine="$(engine_for "$instance")"; [[ "$engine" == pnx ]] || { warn "$id omitido: $instance usa $engine."; return 0; }
  src_type="$(jq -r '.source_type' <<<"$item")"; expected="$(jq -r '.minecraft' <<<"$item")"; [[ "$expected" == "$PNX_EXPECTED_MINECRAFT" ]] || die "$id está catalogado para $expected, no $PNX_EXPECTED_MINECRAFT."
  case "$src_type" in local-maven) artifact="$(build_local_maven "$item")"; actual_ref="$(jq -r '.version' <<<"$item")";; git-gradle) artifact="$(build_git_gradle "$item")"; actual_ref="$(jq -r '.ref' <<<"$item")";; *) die "source_type no soportado: $src_type";; esac
  remove_conflicts "$item"; target="$(target_jar "$item")"; mkdir -p "$(dirname "$target")"; install -m 0644 "$artifact" "$target.tmp"; mv -f "$target.tmp" "$target"; printf '%s\n' "$actual_ref" > "$PLUGIN_STATE/$id.ref"; sha256sum "$target" | awk '{print $1}' > "$PLUGIN_STATE/$id.sha256"; render_internal_config "$id" "$instance"; chown -R bedrock:bedrock "$INSTANCES_DIR/$instance/plugins" "$PLUGIN_STATE"; ok "$id instalado en $instance."
}
sync_plugins(){
  need_tools; local id auto item target wanted installed failures=0
  while IFS= read -r id; do item="$(row "$id")"; auto="$(jq -r '.auto_install' <<<"$item")"; [[ "$auto" == true ]] || continue; [[ "$(engine_for "$(jq -r '.instance' <<<"$item")")" == pnx ]] || continue; target="$(target_jar "$item")"; if [[ "$(jq -r '.source_type' <<<"$item")" == local-maven ]]; then wanted="$(jq -r '.version' <<<"$item")"; else wanted="$(jq -r '.ref' <<<"$item")"; fi; installed="$(cat "$PLUGIN_STATE/$id.ref" 2>/dev/null || true)"; if [[ ! -f "$target" || "$installed" != "$wanted" ]]; then install_one "$id" || failures=$((failures+1)); else remove_conflicts "$item"; render_internal_config "$id" "$(jq -r '.instance' <<<"$item")"; ok "$id ya está fijado en $wanted."; fi; done < <(jq -r '.plugins[].id' "$CATALOG"); ((failures == 0)) || die "Fallaron $failures plugin(s)."
}
doctor(){
  local id item auto instance target wanted installed fail=0
  while IFS= read -r id; do item="$(row "$id")"; auto="$(jq -r '.auto_install' <<<"$item")"; [[ "$auto" == true ]] || continue; instance="$(jq -r '.instance' <<<"$item")"; [[ "$(engine_for "$instance")" == pnx ]] || continue; target="$(target_jar "$item")"; if [[ "$(jq -r '.source_type' <<<"$item")" == local-maven ]]; then wanted="$(jq -r '.version' <<<"$item")"; else wanted="$(jq -r '.ref' <<<"$item")"; fi; installed="$(cat "$PLUGIN_STATE/$id.ref" 2>/dev/null || true)"; if [[ -f "$target" && "$installed" == "$wanted" ]]; then ok "$id: instalado ($instance)"; else warn "$id: faltante/desactualizado ($instance, esperado $wanted)."; fail=$((fail+1)); fi; done < <(jq -r '.plugins[].id' "$CATALOG"); return "$fail"
}
list_plugins(){ printf '\n%-20s %-10s %-9s %-16s %s\n' PLUGIN INSTANCIA AUTO LICENCIA REF; jq -r '.plugins[] | [.id,.instance,(.auto_install|tostring),.license,(.ref // .version)] | @tsv' "$CATALOG" | while IFS=$'\t' read -r a b c d e; do printf '%-20s %-10s %-9s %-16s %s\n' "$a" "$b" "$c" "$d" "$e"; done; }
case "${1:-list}" in list) list_plugins;; sync) sync_plugins;; install) [[ $# -eq 2 ]] || { usage; exit 1; }; need_tools; install_one "$2";; doctor) doctor;; *) usage; exit 1;; esac
