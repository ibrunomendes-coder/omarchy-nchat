# omarchy-nchat

Persistent [nchat](https://github.com/d99kris/nchat) session plus a new-message badge for the [Omarchy](https://omarchy.org) shell bar — without `notify-send` popups stealing your mouse.

![Badge with new-message count](screenshots/badge.png)

Hovering shows the count plus the last sender and message:

![Tooltip with last message](screenshots/tooltip.png)

## Why a persistent session?

nchat only receives messages and runs `desktop_notify_command` while its process is alive. A regular terminal window stops the notification engine when closed.

This plugin keeps nchat inside a detached tmux session. The visible terminal is only a client: closing it leaves nchat connected in the background.

```text
managed tmux session (nchat stays alive)
        │
        ├── desktop_notify_command → notify-hook.sh
        │                              └── ~/.cache/nchat-plugin/state.json
        │                                      │ FileView watch (no polling)
        │                                      └── Omarchy badge + tooltip
        │
        └── click badge → focus/open terminal → tmux attach
                           close terminal ──────┘ (nchat remains alive)
```

## Behavior

| Action | Result |
|---|---|
| Plugin loads | Starts/ensures the `omarchy-nchat` tmux session |
| New notification | Count increments silently; icon lights up with a badge |
| No new notifications | Icon stays visible and dimmed |
| Left click | Focuses or opens a terminal attached to the persistent session; clears the badge only after a successful launch |
| Right click | Clears the badge only |
| Middle click | Rechecks/starts the backend |
| Close terminal | Detaches the visible client; nchat keeps running |

The badge is **notifications since the last successful open**, not nchat's canonical unread count. It follows nchat's `desktop_notify_*` rules and may exclude muted/current-chat messages.

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell`
- [nchat](https://github.com/d99kris/nchat)
- `tmux`, `jq` and `flock`

## Install

### 1. Install the plugin

```bash
git clone https://github.com/ibrunomendes-coder/omarchy-nchat.git
mkdir -p ~/.config/omarchy/plugins/ibrunomendes.nchat
cp omarchy-nchat/{manifest.json,BarWidget.qml,nchat-session.sh} \
  ~/.config/omarchy/plugins/ibrunomendes.nchat/
chmod +x ~/.config/omarchy/plugins/ibrunomendes.nchat/nchat-session.sh
```

### 2. Install the notification hook

```bash
cp omarchy-nchat/notify-hook.sh ~/.config/nchat/
chmod +x ~/.config/nchat/notify-hook.sh
```

### 3. Configure nchat

In `~/.config/nchat/ui.conf`:

```ini
desktop_notify_enabled=1
desktop_notify_command=/home/<you>/.config/nchat/notify-hook.sh '%1' '%2'
desktop_notify_inactive=1
desktop_notify_active_noncurrent=1
terminal_bell_inactive=0
```

Use an absolute path. Restart any running nchat process after changing `ui.conf`.

### 4. Add the widget to the bar

In `~/.config/omarchy/shell.json`, inside any `bar.layout` section:

```json
{
  "id": "ibrunomendes.nchat"
}
```

Then:

```bash
omarchy-shell shell rescanPlugins
omarchy restart shell
```

## Health and control

```bash
# Backend status
~/.config/omarchy/plugins/ibrunomendes.nchat/nchat-session.sh status

# Ensure/start it
~/.config/omarchy/plugins/ibrunomendes.nchat/nchat-session.sh ensure

# Open/focus the attached terminal
~/.config/omarchy/plugins/ibrunomendes.nchat/nchat-session.sh open

# Stop the persistent session
~/.config/omarchy/plugins/ibrunomendes.nchat/nchat-session.sh stop

# Widget IPC
omarchy-shell ibrunomendes.nchat open
omarchy-shell ibrunomendes.nchat clear
omarchy-shell ibrunomendes.nchat refresh
```

## Tests

```bash
./tests/run
```

The suite checks shell/manifest syntax, concurrent hook writes, JSON escaping, private permissions, tmux lifecycle and idempotency.

## Troubleshooting

- **Backend offline:** run `nchat-session.sh status`, then `nchat-session.sh ensure`.
- **“nchat is already running outside the managed tmux session”:** close the standalone nchat, then middle-click the widget or run `ensure` again. This prevents two processes from competing for the same profiles/databases.
- **Badge never lights up:** verify that the managed session is online and inspect `~/.cache/nchat-plugin/state.json` after a real message.
- **Widget vanished after editing QML:** run `omarchy restart shell`; hot-reload can drop a bar slot.
- **Shell logs:** `find /run/user/$(id -u)/quickshell/by-id -name log.log -printf '%T@ %p\n' | sort -rn | head -1`.

## Uninstall

```bash
~/.config/omarchy/plugins/ibrunomendes.nchat/nchat-session.sh stop
rm -rf ~/.config/omarchy/plugins/ibrunomendes.nchat
rm -f ~/.config/nchat/notify-hook.sh
```

Remove `{"id": "ibrunomendes.nchat"}` from `~/.config/omarchy/shell.json`, then restore `desktop_notify_command=` or set `desktop_notify_enabled=0` in nchat.

## License

MIT — see [LICENSE](LICENSE).
