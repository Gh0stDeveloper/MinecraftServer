#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
source_engines

MINIGAME_STATE="$ROOT/minigames"
SKY_MANIFEST="$MINIGAME_STATE/skywars-maps.json"
mkdir -p "$MINIGAME_STATE"
[[ -f "$SKY_MANIFEST" ]] || printf '{"maps":[]}\n' > "$SKY_MANIFEST"

usage(){ cat <<'HELP'
Uso:
  mcserver minigames status
  mcserver minigames prepare
  mcserver minigames import-bedwars /ruta/Mundo
  mcserver minigames import-skywars NOMBRE /ruta/Mundo --spawns "x,y,z;x,y,z;..." --mid "x,y,z"
  mcserver minigames remove-skywars NOMBRE
  mcserver minigames verify

BedWars usa un mundo principal llamado "world" porque SilentBedwars upstream lo exige.
SkyWars puede tener varios mapas; las coordenadas se guardan en un manifiesto administrado.
HELP
}

valid_world(){
  local src="$1"
  [[ -d "$src" && -f "$src/level.dat" && -d "$src/db" ]]
}

remember_active(){ systemctl is-active --quiet "bedrock@$1.service" 2>/dev/null; }

backup_dir(){
  local src="$1" label="$2" stamp out
  [[ -d "$src" ]] || return 0
  stamp="$(date +%Y%m%d-%H%M%S)"; out="$BACKUP_DIR/minigames-$stamp"; mkdir -p "$out"
  tar -C "$(dirname "$src")" -czf "$out/${label}.tar.gz" "$(basename "$src")"
  chown -R bedrock:bedrock "$out"
  ok "Backup: $out/${label}.tar.gz"
}

render_skywars_config(){
  local out="$INSTANCES_DIR/skywars/plugins/PowerSkywars/maps_config.yml"
  mkdir -p "$(dirname "$out")"
  : > "$out"
  while IFS= read -r row; do
    name="$(jq -r '.name' <<<"$row")"
    printf '%s:\n  spawns:\n' "$name" >> "$out"
    jq -c '.spawns[]' <<<"$row" | while IFS= read -r spawn; do
      printf '    - [%s, %s, %s]\n' "$(jq -r '.[0]' <<<"$spawn")" "$(jq -r '.[1]' <<<"$spawn")" "$(jq -r '.[2]' <<<"$spawn")" >> "$out"
    done
    mid="$(jq -c '.mid' <<<"$row")"
    printf '  mid: [%s, %s, %s]\n' "$(jq -r '.[0]' <<<"$mid")" "$(jq -r '.[1]' <<<"$mid")" "$(jq -r '.[2]' <<<"$mid")" >> "$out"
  done < <(jq -c '.maps[]' "$SKY_MANIFEST")
  chown -R bedrock:bedrock "$INSTANCES_DIR/skywars/plugins/PowerSkywars" 2>/dev/null || true
}

refresh_lobby(){
  "$APP_DIR/scripts/render-lobby-config.sh" || true
  local level
  level="$(awk -F= '$1=="level-name"{print substr($0,index($0,"=")+1)}' "$INSTANCES_DIR/lobby/server.properties" 2>/dev/null || true)"
  if [[ -n "$level" && -d "$INSTANCES_DIR/lobby/worlds/$level" ]]; then
    "$APP_DIR/scripts/install-addon.sh" lobby "$ROOT/addons/lobby_bp" >/dev/null || true
    systemctl restart bedrock@lobby.service 2>/dev/null || true
  fi
}

prepare(){
  local props="$INSTANCES_DIR/bedwars/server.properties"
  if [[ -f "$props" ]]; then
    if grep -q '^level-name=' "$props"; then sed -i 's/^level-name=.*/level-name=world/' "$props"; else printf '\nlevel-name=world\n' >> "$props"; fi
    if grep -q '^max-players=' "$props"; then sed -i 's/^max-players=.*/max-players=8/' "$props"; fi
  fi
  mkdir -p "$INSTANCES_DIR/bedwars/plugins/SilentBedwars" "$INSTANCES_DIR/skywars/plugins/PowerSkywars/maps"
  render_skywars_config
  chown -R bedrock:bedrock "$INSTANCES_DIR/bedwars" "$INSTANCES_DIR/skywars" "$MINIGAME_STATE"
  refresh_lobby
  ok 'Estructura de minijuegos preparada.'
}

parse_vec3(){
  local raw="$1"
  [[ "$raw" =~ ^-?[0-9]+,-?[0-9]+,-?[0-9]+$ ]] || die "Vector inválido: $raw (usa x,y,z enteros)"
  printf '[%s]' "${raw//,/","}"
}

import_bedwars(){
  local src="$1" target="$INSTANCES_DIR/bedwars/worlds/world" was_active=0
  src="$(realpath "$src")"; valid_world "$src" || die 'El mapa BedWars debe contener level.dat y db/.'
  remember_active bedwars && was_active=1 || true
  systemctl stop bedrock@bedwars.service 2>/dev/null || true
  backup_dir "$target" bedwars-world
  mkdir -p "$(dirname "$target")"; rm -rf "$target"; mkdir -p "$target"; rsync -a "$src/" "$target/"
  chown -R bedrock:bedrock "$target"
  prepare
  ((was_active)) && systemctl start bedrock@bedwars.service || true
  ok 'Mapa BedWars importado como world. Verifica que sus bases coincidan con la configuración de la arena.'
}

import_skywars(){
  local name="$1" src="$2"; shift 2
  local spawns="" mid=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --spawns) spawns="${2:-}"; shift 2;;
      --mid) mid="${2:-}"; shift 2;;
      *) die "Opción desconocida: $1";;
    esac
  done
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die 'NOMBRE solo puede contener letras, números, _ y -.'
  [[ -n "$spawns" && -n "$mid" ]] || die 'SkyWars requiere --spawns y --mid.'
  src="$(realpath "$src")"; valid_world "$src" || die 'El mapa SkyWars debe contener level.dat y db/.'

  local spawn_json='[]' count=0 one vec
  IFS=';' read -ra SPAWN_LIST <<< "$spawns"
  for one in "${SPAWN_LIST[@]}"; do
    vec="$(parse_vec3 "$one")"; spawn_json="$(jq -c --argjson v "$vec" '. + [$v]' <<<"$spawn_json")"; count=$((count+1))
  done
  ((count >= 2)) || die 'SkyWars necesita al menos 2 spawns.'
  local mid_json; mid_json="$(parse_vec3 "$mid")"

  local target="$INSTANCES_DIR/skywars/plugins/PowerSkywars/maps/$name" was_active=0 tmp
  remember_active skywars && was_active=1 || true
  systemctl stop bedrock@skywars.service 2>/dev/null || true
  backup_dir "$target" "skywars-$name"
  rm -rf "$target"; mkdir -p "$target"; rsync -a "$src/" "$target/"

  tmp="$(mktemp)"
  jq --arg name "$name" --argjson spawns "$spawn_json" --argjson mid "$mid_json" '
    .maps = ([.maps[] | select(.name != $name)] + [{name:$name,spawns:$spawns,mid:$mid}])
  ' "$SKY_MANIFEST" > "$tmp"
  mv "$tmp" "$SKY_MANIFEST"
  render_skywars_config
  chown -R bedrock:bedrock "$target" "$SKY_MANIFEST" "$INSTANCES_DIR/skywars/plugins/PowerSkywars"
  refresh_lobby
  ((was_active)) && systemctl start bedrock@skywars.service || true
  ok "Mapa SkyWars '$name' importado con $count spawns."
}

remove_skywars(){
  local name="$1" target="$INSTANCES_DIR/skywars/plugins/PowerSkywars/maps/$name" tmp
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die 'Nombre inválido.'
  backup_dir "$target" "skywars-$name"
  rm -rf "$target"
  tmp="$(mktemp)"; jq --arg name "$name" '.maps=[.maps[] | select(.name != $name)]' "$SKY_MANIFEST" > "$tmp"; mv "$tmp" "$SKY_MANIFEST"
  render_skywars_config; refresh_lobby
  ok "Mapa SkyWars '$name' eliminado."
}

status(){
  local bw='NO LISTO' sw='NO LISTO' pvp='NO LISTO' sw_count
  [[ -f "$INSTANCES_DIR/pvp/plugins/nexora-practice.jar" ]] && pvp='LISTO'
  [[ -f "$INSTANCES_DIR/bedwars/plugins/silentbedwars.jar" && -f "$INSTANCES_DIR/bedwars/worlds/world/level.dat" ]] && bw='LISTO'
  sw_count="$(jq '.maps|length' "$SKY_MANIFEST" 2>/dev/null || echo 0)"
  [[ -f "$INSTANCES_DIR/skywars/plugins/powerskywars.jar" && "$sw_count" -gt 0 ]] && sw='LISTO'
  printf '\n%-10s %-12s %s\n' MODO ESTADO DETALLE
  printf '%-10s %-12s %s\n' '----' '------' '-------'
  printf '%-10s %-12s %s\n' PvP "$pvp" '1v1 / 2v2 / 4v4, arenas autogeneradas'
  printf '%-10s %-12s %s\n' BedWars "$bw" 'mundo requerido: worlds/world'
  printf '%-10s %-12s %s\n' SkyWars "$sw" "$sw_count mapa(s) importado(s)"
  printf '\nHost: %s  IP: %s  Dominio: %s\n' "$PUBLIC_HOST" "${PUBLIC_IP:-?}" "${PUBLIC_DOMAIN:-?}"
}

verify(){
  local fail=0
  [[ -f "$INSTANCES_DIR/pvp/plugins/nexora-practice.jar" ]] || { warn 'Falta NexoraPractice.'; fail=$((fail+1)); }
  if [[ -f "$INSTANCES_DIR/bedwars/plugins/silentbedwars.jar" ]]; then
    [[ -f "$INSTANCES_DIR/bedwars/worlds/world/level.dat" ]] || { warn 'BedWars no tiene mapa world importado.'; fail=$((fail+1)); }
  fi
  if [[ -f "$INSTANCES_DIR/skywars/plugins/powerskywars.jar" ]]; then
    jq -e '.maps | type=="array"' "$SKY_MANIFEST" >/dev/null || { warn 'Manifiesto SkyWars inválido.'; fail=$((fail+1)); }
    while IFS= read -r name; do [[ -f "$INSTANCES_DIR/skywars/plugins/PowerSkywars/maps/$name/level.dat" ]] || { warn "Falta mundo SkyWars $name."; fail=$((fail+1)); }; done < <(jq -r '.maps[].name' "$SKY_MANIFEST")
  fi
  ((fail == 0)) && ok 'Minijuegos sin bloqueos de configuración.' || die "Se encontraron $fail problema(s) de minijuegos."
}

case "${1:-status}" in
  status) status;;
  prepare) prepare;;
  import-bedwars) [[ $# -eq 2 ]] || { usage; exit 1; }; import_bedwars "$2";;
  import-skywars) [[ $# -ge 3 ]] || { usage; exit 1; }; shift; import_skywars "$@";;
  remove-skywars) [[ $# -eq 2 ]] || { usage; exit 1; }; remove_skywars "$2";;
  verify) verify;;
  *) usage; exit 1;;
esac
