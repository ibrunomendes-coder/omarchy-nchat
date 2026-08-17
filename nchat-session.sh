#!/usr/bin/env bash
set -Eeuo pipefail

# Mantém o nchat vivo em uma sessão tmux destacada e integra o hook oficial
# desktop_notify_command. O primeiro `open` configura o nchat com backup.

umask 077

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
notify_hook="$script_dir/notify-hook.sh"
session="${OMARCHY_NCHAT_SESSION:-omarchy-nchat}"
app_id="${OMARCHY_NCHAT_APP_ID:-org.omarchy.nchat}"
nchat_command="${OMARCHY_NCHAT_COMMAND:-nchat}"
nchat_config_dir="${NCHAT_CONFIG_DIR:-$HOME/.config/nchat}"
ui_config="$nchat_config_dir/ui.conf"
ui_backup="$nchat_config_dir/ui.conf.omarchy-nchat.bak"
config_lock="$nchat_config_dir/.omarchy-nchat.lock"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/omarchy-nchat-${UID}"
session_lock="$runtime_dir/session.lock"
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nchat-plugin"
state_file="$state_dir/state.json"
state_lock="$state_dir/.lock"
expected_notify_command="$notify_hook '%1' '%2'"

[[ "$session" =~ ^[A-Za-z0-9_.-]+$ ]] || {
  echo "invalid tmux session name: $session" >&2
  exit 64
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 127
  }
}

config_has() {
  local key="$1"
  local expected="$2"
  [[ -f "$ui_config" ]] && grep -Fqx "$key=$expected" "$ui_config"
}

configured() {
  [[ "${OMARCHY_NCHAT_SKIP_CONFIG_CHECK:-0}" == "1" ]] && return 0
  [[ -x "$notify_hook" ]] || return 1
  config_has desktop_notify_enabled 1 \
    && config_has desktop_notify_command "$expected_notify_command" \
    && config_has desktop_notify_inactive 1 \
    && config_has desktop_notify_active_noncurrent 1 \
    && config_has terminal_bell_inactive 0
}

configure_nchat() {
  require awk
  require flock

  [[ -f "$ui_config" ]] || {
    echo "nchat is not configured yet: missing $ui_config" >&2
    echo "run 'nchat --setup' first, then click the widget again" >&2
    exit 3
  }
  [[ -x "$notify_hook" ]] || {
    echo "notification hook is missing or not executable: $notify_hook" >&2
    exit 3
  }

  configured && return 0

  install -d -m 700 "$nchat_config_dir"
  touch "$config_lock"
  chmod 600 "$config_lock"

  (
    flock -w 10 9 || {
      echo "timed out waiting for nchat config lock" >&2
      exit 75
    }

    configured && exit 0
    [[ -f "$ui_backup" ]] || cp -a -- "$ui_config" "$ui_backup"

    tmp=$(mktemp "$nchat_config_dir/.ui.conf.XXXXXX")
    trap 'rm -f -- "$tmp"' EXIT

    awk -v notify="$expected_notify_command" '
      BEGIN {
        desired["desktop_notify_enabled"] = "1"
        desired["desktop_notify_command"] = notify
        desired["desktop_notify_inactive"] = "1"
        desired["desktop_notify_active_noncurrent"] = "1"
        desired["terminal_bell_inactive"] = "0"
        order[1] = "desktop_notify_enabled"
        order[2] = "desktop_notify_command"
        order[3] = "desktop_notify_inactive"
        order[4] = "desktop_notify_active_noncurrent"
        order[5] = "terminal_bell_inactive"
      }
      {
        equals = index($0, "=")
        key = equals > 0 ? substr($0, 1, equals - 1) : ""
        if (key in desired) {
          if (!seen[key]) print key "=" desired[key]
          seen[key] = 1
          next
        }
        print
      }
      END {
        for (i = 1; i <= 5; i++) {
          key = order[i]
          if (!seen[key]) print key "=" desired[key]
        }
      }
    ' "$ui_config" > "$tmp"

    chmod --reference="$ui_config" "$tmp"
    mv -f -- "$tmp" "$ui_config"
    trap - EXIT
  ) 9>"$config_lock"
}

unconfigure_nchat() {
  require awk
  require flock

  [[ -f "$ui_config" ]] || return 0
  if [[ ! -f "$ui_backup" ]]; then
    configured || return 0
    echo "cannot restore nchat config: missing backup $ui_backup" >&2
    exit 4
  fi

  touch "$config_lock"
  chmod 600 "$config_lock"

  (
    flock -w 10 9 || exit 75
    tmp=$(mktemp "$nchat_config_dir/.ui.conf.XXXXXX")
    trap 'rm -f -- "$tmp"' EXIT

    # Restaura apenas as cinco chaves possuídas pelo plugin. Alterações feitas
    # depois da instalação em qualquer outra chave permanecem intactas.
    awk '
      BEGIN {
        owned["desktop_notify_enabled"] = 1
        owned["desktop_notify_command"] = 1
        owned["desktop_notify_inactive"] = 1
        owned["desktop_notify_active_noncurrent"] = 1
        owned["terminal_bell_inactive"] = 1
        order[1] = "desktop_notify_enabled"
        order[2] = "desktop_notify_command"
        order[3] = "desktop_notify_inactive"
        order[4] = "desktop_notify_active_noncurrent"
        order[5] = "terminal_bell_inactive"
      }
      NR == FNR {
        equals = index($0, "=")
        key = equals > 0 ? substr($0, 1, equals - 1) : ""
        if (key in owned) {
          original[key] = $0
          original_present[key] = 1
        }
        next
      }
      {
        equals = index($0, "=")
        key = equals > 0 ? substr($0, 1, equals - 1) : ""
        if (key in owned) {
          if (!restored[key] && original_present[key]) print original[key]
          restored[key] = 1
          next
        }
        print
      }
      END {
        for (i = 1; i <= 5; i++) {
          key = order[i]
          if (!restored[key] && original_present[key]) print original[key]
        }
      }
    ' "$ui_backup" "$ui_config" > "$tmp"

    chmod --reference="$ui_config" "$tmp"
    mv -f -- "$tmp" "$ui_config"
    rm -f -- "$ui_backup"
    trap - EXIT
  ) 9>"$config_lock"
}

managed_online() {
  tmux has-session -t "$session" 2>/dev/null
}

external_nchat_running() {
  [[ "${OMARCHY_NCHAT_SKIP_EXTERNAL_CHECK:-0}" == "1" ]] && return 1
  pgrep -x nchat >/dev/null 2>&1
}

ensure_session() {
  require tmux
  require "${nchat_command%% *}"
  configured || {
    echo "nchat integration is not configured; click the widget once to finish setup" >&2
    exit 3
  }

  install -d -m 700 "$runtime_dir"
  touch "$session_lock"
  chmod 600 "$session_lock"

  (
    flock -w 10 9 || {
      echo "timed out waiting for session lock" >&2
      exit 75
    }

    managed_online && exit 0

    # Evita duas instâncias disputando os bancos/perfis do nchat.
    if external_nchat_running; then
      echo "nchat is already running outside the managed tmux session" >&2
      exit 2
    fi

    # Não deixar o backend herdar o descritor do flock; caso contrário a
    # sessão seguraria o lock até o nchat encerrar.
    tmux new-session -d -s "$session" "$nchat_command" 9>&-

    for _ in $(seq 1 20); do
      managed_online && exit 0
      sleep 0.1
    done

    echo "tmux session failed to start" >&2
    exit 1
  ) 9>"$session_lock"
}

setup_and_start() {
  local needs_restart=0
  configured || needs_restart=1
  configure_nchat

  if (( needs_restart )) && managed_online; then
    tmux kill-session -t "$session" 2>/dev/null || true
  fi

  ensure_session
}

print_status() {
  require tmux

  local is_configured=false
  configured && is_configured=true

  if managed_online; then
    printf '{"online":true,"managed":true,"external":false,"configured":%s,"session":"%s"}\n' "$is_configured" "$session"
  elif external_nchat_running; then
    printf '{"online":true,"managed":false,"external":true,"configured":%s,"session":"%s"}\n' "$is_configured" "$session"
  else
    printf '{"online":false,"managed":false,"external":false,"configured":%s,"session":"%s"}\n' "$is_configured" "$session"
  fi
}

open_session() {
  require omarchy
  setup_and_start

  # ID exclusivo evita que o focus case com uma aba de navegador chamada nchat.
  exec omarchy launch or focus tui --app-id="$app_id" \
    tmux attach-session -t "$session"
}

clear_state() {
  require flock
  install -d -m 700 "$state_dir"
  touch "$state_lock"
  chmod 600 "$state_lock"

  (
    flock -w 5 9 || exit 75
    rm -f -- "$state_file"
  ) 9>"$state_lock"
}

stop_session() {
  require tmux
  tmux kill-session -t "$session" 2>/dev/null || true
}

uninstall_plugin() {
  stop_session
  unconfigure_nchat
  clear_state
}

case "${1:-}" in
  setup) setup_and_start ;;
  ensure) ensure_session ;;
  open) open_session ;;
  status) print_status ;;
  clear) clear_state ;;
  stop) stop_session ;;
  uninstall) uninstall_plugin ;;
  *)
    echo "usage: $0 {setup|ensure|open|status|clear|stop|uninstall}" >&2
    exit 64
    ;;
esac
