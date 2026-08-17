#!/usr/bin/env bash
set -Eeuo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
session="omarchy-nchat-test-$$"

export HOME="$tmp/home"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_RUNTIME_DIR="$tmp/runtime"
export OMARCHY_NCHAT_SESSION="$session"
export OMARCHY_NCHAT_COMMAND="sleep 300"
export OMARCHY_NCHAT_SKIP_EXTERNAL_CHECK=1
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

cleanup() {
  "$repo/nchat-session.sh" stop >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

[[ $("$repo/nchat-session.sh" status | jq -r '.online') == false ]]
"$repo/nchat-session.sh" ensure

tmux has-session -t "$session"
status=$("$repo/nchat-session.sh" status)
[[ $(jq -r '.online' <<<"$status") == true ]]
[[ $(jq -r '.managed' <<<"$status") == true ]]

# Idempotência: um segundo ensure não cria outra sessão.
"$repo/nchat-session.sh" ensure
[[ $(tmux list-sessions -F '#S' | grep -cx "$session") == 1 ]]

"$repo/nchat-session.sh" stop
[[ $("$repo/nchat-session.sh" status | jq -r '.online') == false ]]

echo "PASS session: ensure, status, idempotência e stop"
