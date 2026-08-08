#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
require_root
source_config
source_engines
usage(){ cat <<'HELP'
Uso:
  mcserver engine status
  mcserver engine set <pvp|bedwars|skywars> <bds|pnx>
  mcserver engine prepare [instancia]

Lobby y Survival están bloqueados a BDS.
HELP
}
prepare_pnx(){
  local instance="$1" target="$INSTANCES_DIR/$instance"
  mkdir -p "$target/plugins" "$target/worlds"
  if [[ ! -f "$target/pnx.yml" ]]; then
    cat > "$target/pnx.yml" <<'YAML'
settings:
  language: spa
  forceServerTranslate: false
  shutdownMessage: Servidor cerrado
  queryPlugins: false
  deprecatedVerbose: true
  asyncWorkers: auto
  safeSpawn: true
  installSpark: true
  waterdogpe: false
  autosave: 6000
  saveUnknownBlock: true
network-settings:
  compressionLevel: 7
  zlibProvider: 3
  snappy: false
  compressionBufferSize: 1048576
  maxDecompressSize: 67108864
  packetLimit: 240
debug-settings:
  level: INFO
  command: false
  ignoredPackets: []
  allowBeta: false
level-settings:
  autoTickRate: true
  autoTickRateLimit: 20
  baseTickRate: 1
  alwaysTickPlayers: false
  enableRedstone: true
  tickRedstone: true
  chunkUnloadDelay: 15000
  levelThread: false
chunk-settings:
  perTickSend: 8
  spawnThreshold: 56
  chunksPerTicks: 40
  tickRadius: 3
  lightUpdates: true
  clearTickList: false
  generationQueueSize: 16
player-settings:
  savePlayerData: true
  skinChangeCooldown: 30
  forceSkinTrusted: false
  checkMovement: true
  spawnRadius: 16
gameplay-settings:
  enableCommandBlocks: true
YAML
  fi
  chown -R bedrock:bedrock "$target"
}
apply_current_bds(){
  local instance="$1" release
  release="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
  [[ -n "$release" && -x "$release/bedrock_server" ]] || die "No hay runtime BDS actual. Ejecuta sudo mcserver update bds."
  rsync -a "$release/" "$INSTANCES_DIR/$instance/" --exclude='server.properties' --exclude='allowlist.json' --exclude='permissions.json' --exclude='worlds/' --exclude='behavior_packs/' --exclude='resource_packs/' --exclude='development_behavior_packs/' --exclude='development_resource_packs/' --exclude='plugins/' --exclude='pnx.yml'
  chmod +x "$INSTANCES_DIR/$instance/bedrock_server"
}
status(){
  printf '\n%-10s %-8s %-12s\n' INSTANCIA MOTOR ESTADO
  printf '%-10s %-8s %-12s\n' '---------' '-----' '------'
  local i e state
  for i in "${INSTANCES[@]}"; do e="$(engine_for "$i")"; systemctl is-active --quiet "bedrock@$i.service" 2>/dev/null && state=ONLINE || state=OFFLINE; printf '%-10s %-8s %-12s\n' "$i" "$e" "$state"; done
  printf '\nBDS: %s\nPNX: %s\n' "$(current_bds_version)" "$(current_pnx_version)"
}
set_engine(){
  local instance="$1" engine="$2" key old backup was_active target_was_active=0
  [[ "$instance" == pvp || "$instance" == bedwars || "$instance" == skywars ]] || die "Solo pvp, bedwars y skywars pueden cambiar de motor."
  [[ "$engine" == bds || "$engine" == pnx ]] || die "Motor inválido: $engine"
  mkdir -p "$CONFIG_DIR"; [[ -f "$ENGINES_FILE" ]] || cp "$APP_DIR/config/engines.env" "$ENGINES_FILE"
  old="$(engine_for "$instance")"; [[ "$old" != "$engine" ]] || { ok "$instance ya usa $engine."; exit 0; }
  key="${instance^^}_ENGINE"; lock_manager
  was_active="$(active_instances)"
  grep -qx "$instance" <<<"$was_active" && target_was_active=1 || true
  stop_network
  backup="$("$APP_DIR/scripts/network-backup.sh" --online-stopped | tail -n1)"
  if grep -q "^${key}=" "$ENGINES_FILE"; then sed -i "s/^${key}=.*/${key}=${engine}/" "$ENGINES_FILE"; else printf '%s=%s\n' "$key" "$engine" >> "$ENGINES_FILE"; fi
  if [[ "$engine" == pnx ]]; then
    if [[ ! -f "$PNX_CURRENT_LINK/powernukkitx-shaded.jar" ]]; then
      sed -i "s/^${key}=.*/${key}=${old}/" "$ENGINES_FILE"
      start_instance_list "$was_active"
      die "PNX no está instalado. Ejecuta sudo mcserver update pnx."
    fi
    prepare_pnx "$instance"
  else
    apply_current_bds "$instance"
  fi
  chown root:bedrock "$ENGINES_FILE"; chmod 0640 "$ENGINES_FILE"
  start_instance_list "$was_active"
  if (( target_was_active )); then
    sleep 3
    if ! systemctl is-active --quiet "bedrock@$instance.service"; then
      stop_network
      sed -i "s/^${key}=.*/${key}=${old}/" "$ENGINES_FILE"
      [[ "$old" == bds ]] && apply_current_bds "$instance" || prepare_pnx "$instance"
      start_instance_list "$was_active"
      die "$instance no pudo iniciar con $engine. Se restauró $old. Backup: $backup"
    fi
  fi
  ok "$instance usa ahora $engine. Se conservó el estado online/offline previo. Backup: $backup"
}
case "${1:-status}" in
  status) status;;
  set) [[ $# -eq 3 ]] || { usage; exit 1; }; set_engine "$2" "$3";;
  prepare) if [[ -n "${2:-}" ]]; then prepare_pnx "$2"; else for i in pvp bedwars skywars; do prepare_pnx "$i"; done; fi;;
  *) usage; exit 1;;
esac
