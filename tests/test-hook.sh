#!/usr/bin/env bash
set -Eeuo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CACHE_HOME="$tmp/cache"
mkdir -p "$HOME"

for i in $(seq 1 20); do
  "$repo/notify-hook.sh" "Sender $i" "Message $i with ' and \"" &
done
wait

state="$XDG_CACHE_HOME/nchat-plugin/state.json"
[[ $(jq -r '.count' "$state") == 20 ]]
[[ $(stat -c %a "$XDG_CACHE_HOME/nchat-plugin") == 700 ]]
[[ $(stat -c %a "$state") == 600 ]]
[[ $(stat -c %a "$XDG_CACHE_HOME/nchat-plugin/.lock") == 600 ]]

OMARCHY_NCHAT_SKIP_EXTERNAL_CHECK=1 "$repo/nchat-session.sh" clear
[[ ! -e "$state" ]]

echo "PASS hook: concorrência, JSON, permissões e clear"
