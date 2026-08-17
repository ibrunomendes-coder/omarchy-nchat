#!/usr/bin/env bash
set -Eeuo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)

bash -n "$repo/notify-hook.sh" "$repo/nchat-session.sh"
jq -e . "$repo/manifest.json" >/dev/null

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$repo"
fi

echo "PASS static: bash, JSON e manifest"
