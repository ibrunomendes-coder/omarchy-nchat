#!/usr/bin/env bash
set -Eeuo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
session="omarchy-nchat-setup-test-$$"

export HOME="$tmp/home"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_RUNTIME_DIR="$tmp/runtime"
export OMARCHY_NCHAT_SESSION="$session"
export OMARCHY_NCHAT_COMMAND="sleep 300"
export OMARCHY_NCHAT_SKIP_EXTERNAL_CHECK=1
mkdir -p "$HOME/.config/nchat" "$XDG_RUNTIME_DIR"
chmod 700 "$HOME/.config/nchat" "$XDG_RUNTIME_DIR"

cat > "$HOME/.config/nchat/ui.conf" <<'CONF'
desktop_notify_enabled=0
desktop_notify_command=
desktop_notify_inactive=0
desktop_notify_active_noncurrent=0
terminal_bell_inactive=1
custom_setting=preserved
CONF
chmod 600 "$HOME/.config/nchat/ui.conf"

cleanup() {
  "$repo/nchat-session.sh" stop >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

"$repo/nchat-session.sh" setup

config="$HOME/.config/nchat/ui.conf"
backup="$config.omarchy-nchat.bak"
expected="$repo/notify-hook.sh '%1' '%2'"

grep -Fqx 'desktop_notify_enabled=1' "$config"
grep -Fqx "desktop_notify_command=$expected" "$config"
grep -Fqx 'desktop_notify_inactive=1' "$config"
grep -Fqx 'desktop_notify_active_noncurrent=1' "$config"
grep -Fqx 'terminal_bell_inactive=0' "$config"
grep -Fqx 'custom_setting=preserved' "$config"
[[ -f "$backup" ]]
[[ $(stat -c %a "$config") == 600 ]]
[[ $(grep -c '^desktop_notify_command=' "$config") == 1 ]]

backup_hash=$(sha256sum "$backup" | cut -d' ' -f1)
"$repo/nchat-session.sh" setup
[[ $(sha256sum "$backup" | cut -d' ' -f1) == "$backup_hash" ]]
[[ $(grep -c '^desktop_notify_command=' "$config") == 1 ]]

status=$("$repo/nchat-session.sh" status)
[[ $(jq -r '.configured' <<<"$status") == true ]]
[[ $(jq -r '.managed' <<<"$status") == true ]]

# Uninstall restaura apenas chaves possuídas pelo plugin e preserva mudanças
# posteriores em configurações não relacionadas.
sed -i 's/custom_setting=preserved/custom_setting=changed_after_setup/' "$config"
"$repo/nchat-session.sh" uninstall

grep -Fqx 'desktop_notify_enabled=0' "$config"
grep -Fqx 'desktop_notify_command=' "$config"
grep -Fqx 'desktop_notify_inactive=0' "$config"
grep -Fqx 'desktop_notify_active_noncurrent=0' "$config"
grep -Fqx 'terminal_bell_inactive=1' "$config"
grep -Fqx 'custom_setting=changed_after_setup' "$config"
[[ ! -e "$backup" ]]
[[ $("$repo/nchat-session.sh" status | jq -r '.managed') == false ]]

echo "PASS setup: backup, patch atômico, idempotência, sessão e uninstall"
