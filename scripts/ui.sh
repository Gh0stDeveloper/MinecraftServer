#!/usr/bin/env bash
# Shared terminal UI for MinecraftServer. Safe to source from scripts using set -u.

_MCS_UI_TTY=0
[[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]] && _MCS_UI_TTY=1

if ((_MCS_UI_TTY)); then
  UI_RESET=$'\033[0m'
  UI_BOLD=$'\033[1m'
  UI_DIM=$'\033[2m'
  UI_CYAN=$'\033[38;5;45m'
  UI_VIOLET=$'\033[38;5;141m'
  UI_PINK=$'\033[38;5;213m'
  UI_AMBER=$'\033[38;5;220m'
  UI_RED=$'\033[38;5;203m'
  UI_WHITE=$'\033[97m'
  UI_GRAY=$'\033[38;5;245m'
else
  UI_RESET="" UI_BOLD="" UI_DIM="" UI_CYAN="" UI_VIOLET="" UI_PINK="" UI_AMBER="" UI_RED="" UI_WHITE="" UI_GRAY=""
fi

ui_banner(){
  local subtitle="${1:-Instalador y administrador de Minecraft Bedrock}"
  printf '\n%b╭────────────────────────────────────────────────────────╮%b\n' "$UI_VIOLET$UI_BOLD" "$UI_RESET"
  printf '%b│%b  %bNEXORA · BEDROCK NETWORK%b%-29s%b │%b\n' "$UI_VIOLET$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$UI_RESET" "" "$UI_VIOLET$UI_BOLD" "$UI_RESET"
  printf '%b│%b  %-54s%b │%b\n' "$UI_VIOLET$UI_BOLD" "$UI_RESET$UI_GRAY" "$subtitle" "$UI_VIOLET$UI_BOLD" "$UI_RESET"
  printf '%b╰────────────────────────────────────────────────────────╯%b\n\n' "$UI_VIOLET$UI_BOLD" "$UI_RESET"
}

ui_section(){ printf '\n%b%s%b\n' "$UI_PINK$UI_BOLD" "━━ $*" "$UI_RESET"; }
ui_step(){ printf '%b[◆]%b %b%s%b\n' "$UI_CYAN$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$*" "$UI_RESET"; }
ui_ok(){ printf '%b[✓]%b %b%s%b\n' "$UI_VIOLET$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$*" "$UI_RESET"; }
ui_warn(){ printf '%b[!]%b %b%s%b\n' "$UI_AMBER$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$*" "$UI_RESET" >&2; }
ui_error(){ printf '%b[×]%b %b%s%b\n' "$UI_RED$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$*" "$UI_RESET" >&2; }
ui_note(){ printf '%b[→]%b %b%s%b\n' "$UI_GRAY$UI_BOLD" "$UI_RESET" "$UI_GRAY" "$*" "$UI_RESET"; }
ui_kv(){ printf '    %b%-16s%b %b%s%b\n' "$UI_GRAY$UI_BOLD" "$1" "$UI_RESET" "$UI_WHITE" "$2" "$UI_RESET"; }

ui_log_dir(){
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then printf '%s' '/var/log/mcserver'; else printf '%s' "${TMPDIR:-/tmp}/mcserver-${UID:-user}"; fi
}

ui_run_task(){
  local label="$1"; shift
  local log_dir log_file rc=0
  log_dir="$(ui_log_dir)"
  mkdir -p "$log_dir" 2>/dev/null || true
  log_file="$log_dir/tasks.log"

  if [[ "${MCSERVER_VERBOSE:-0}" == "1" ]]; then
    ui_step "$label"
    "$@"
    rc=$?
  elif ((_MCS_UI_TTY)); then
    printf '%b[◆]%b %b%s...%b' "$UI_CYAN$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$label" "$UI_RESET"
    "$@" >>"$log_file" 2>&1 || rc=$?
    if ((rc == 0)); then
      printf '\r\033[K%b[✓]%b %b%s%b\n' "$UI_VIOLET$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$label" "$UI_RESET"
    else
      printf '\r\033[K%b[×]%b %b%s%b\n' "$UI_RED$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$label" "$UI_RESET" >&2
    fi
  else
    ui_step "$label"
    "$@" >>"$log_file" 2>&1 || rc=$?
    ((rc == 0)) && ui_ok "$label"
  fi

  if ((rc != 0)); then
    ui_error "La tarea falló. Últimas líneas del diagnóstico:"
    tail -n 30 "$log_file" >&2 2>/dev/null || true
    ui_note "Log completo: $log_file" >&2
    return "$rc"
  fi
}

ui_prompt(){
  local prompt="$1" default="${2:-}" value
  if [[ -n "$default" ]]; then
    printf '%b?%b %b%s%b %b[%s]%b: ' "$UI_CYAN$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$prompt" "$UI_RESET" "$UI_GRAY" "$default" "$UI_RESET" >/dev/tty
  else
    printf '%b?%b %b%s%b: ' "$UI_CYAN$UI_BOLD" "$UI_RESET" "$UI_WHITE$UI_BOLD" "$prompt" "$UI_RESET" >/dev/tty
  fi
  IFS= read -r value </dev/tty
  printf '%s' "${value:-$default}"
}
