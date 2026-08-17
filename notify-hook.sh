#!/usr/bin/env bash
set -Eeuo pipefail

# Hook do desktop_notify_command do nchat. Recebe '%1' (remetente) e '%2'
# (mensagem) e grava o estado consumido pelo widget da barra Omarchy.

umask 077

state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nchat-plugin"
state_file="$state_dir/state.json"
lock_file="$state_dir/.lock"

command -v jq >/dev/null 2>&1 || exit 127
command -v flock >/dev/null 2>&1 || exit 127

install -d -m 700 "$state_dir"
touch "$lock_file"
chmod 600 "$lock_file"

sender="${1:-}"
text="${2:-}"

(
  flock -w 5 9 || exit 75

  count=0
  if [[ -f "$state_file" ]]; then
    count=$(jq -r '.count // 0' "$state_file" 2>/dev/null || printf '0')
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
  fi
  count=$((count + 1))

  tmp=$(mktemp "$state_dir/.state.XXXXXX")
  trap 'rm -f -- "$tmp"' EXIT

  jq -n \
    --arg sender "$sender" \
    --arg text "$text" \
    --argjson count "$count" \
    --argjson ts "$(date +%s)" \
    '{count: $count, sender: $sender, text: $text, ts: $ts}' > "$tmp"

  chmod 600 "$tmp"
  mv -f -- "$tmp" "$state_file"
  trap - EXIT
) 9>"$lock_file"
