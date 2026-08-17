#!/bin/bash

# Hook de notificação do nchat (desktop_notify_command).
# Recebe '%1' (remetente) e '%2' (mensagem) e grava o estado de não-lidas em
# ~/.cache/nchat-plugin/state.json, lido pelo plugin ibrunomendes.nchat da
# barra Omarchy. Substitui o notify-send: nenhum popup é disparado.

state_dir="$HOME/.cache/nchat-plugin"
state_file="$state_dir/state.json"
lock_file="$state_dir/.lock"

mkdir -p "$state_dir"

sender="${1:-}"
text="${2:-$1}" # alguns fluxos enviam só um argumento

(
  flock -w 5 9 || exit 1

  count=0
  if [[ -f "$state_file" ]]; then
    count=$(jq -r '.count // 0' "$state_file" 2>/dev/null)
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
  fi
  count=$((count + 1))

  tmp=$(mktemp "$state_dir/.state.XXXXXX") || exit 1
  jq -n \
    --arg sender "$sender" \
    --arg text "$text" \
    --argjson count "$count" \
    --argjson ts "$(date +%s)" \
    '{count: $count, sender: $sender, text: $text, ts: $ts}' > "$tmp"
  mv -f "$tmp" "$state_file"
) 9>"$lock_file"
