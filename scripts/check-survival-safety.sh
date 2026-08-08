#!/usr/bin/env bash
set -euo pipefail
FILE="${1:-/opt/bedrock-network/instances/survival/server.properties}"
[[ -f "$FILE" ]] || { echo "No existe $FILE" >&2; exit 1; }
FAIL=0
check() {
  local key="$1" expected="$2" actual
  actual="$(awk -F= -v k="$key" '$1==k{print substr($0,index($0,"=")+1)}' "$FILE" | tail -n1)"
  if [[ "$actual" == "$expected" ]]; then
    printf '[OK] %s=%s\n' "$key" "$actual"
  else
    printf '[ERROR] %s=%s (debe ser %s)\n' "$key" "$actual" "$expected"
    FAIL=1
  fi
}
check allow-cheats false
check force-gamemode false
check gamemode survival
check online-mode true
check allow-list true
exit "$FAIL"
