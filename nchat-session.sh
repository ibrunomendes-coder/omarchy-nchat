#!/usr/bin/env bash
set -Eeuo pipefail

# Mantém o nchat vivo em uma sessão tmux destacada. O terminal visível é apenas
# um cliente da sessão: fechá-lo não encerra o nchat nem as notificações.

umask 077

session="${OMARCHY_NCHAT_SESSION:-omarchy-nchat}"
app_id="${OMARCHY_NCHAT_APP_ID:-org.omarchy.nchat}"
nchat_command="${OMARCHY_NCHAT_COMMAND:-nchat}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/omarchy-nchat-${UID}"
session_lock="$runtime_dir/session.lock"
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nchat-plugin"
state_file="$state_dir/state.json"
state_lock="$state_dir/.lock"

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

managed_online() {
  tmux has-session -t "$session" 2>/dev/null
}

external_nchat_running() {
  [[ "${OMARCHY_NCHAT_SKIP_EXTERNAL_CHECK:-0}" == "1" ]] && return 1
  pgrep -x nchat >/dev/null 2>&1
}

ensure_session() {
  require tmux
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

print_status() {
  require tmux

  if managed_online; then
    printf '{"online":true,"managed":true,"external":false,"session":"%s"}\n' "$session"
  elif external_nchat_running; then
    printf '{"online":true,"managed":false,"external":true,"session":"%s"}\n' "$session"
  else
    printf '{"online":false,"managed":false,"external":false,"session":"%s"}\n' "$session"
  fi
}

open_session() {
  require omarchy
  ensure_session

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

case "${1:-}" in
  ensure) ensure_session ;;
  open) open_session ;;
  status) print_status ;;
  clear) clear_state ;;
  stop) stop_session ;;
  *)
    echo "usage: $0 {ensure|open|status|clear|stop}" >&2
    exit 64
    ;;
esac
