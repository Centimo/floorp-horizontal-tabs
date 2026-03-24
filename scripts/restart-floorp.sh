#!/bin/bash
# Restart Floorp browser while preserving window positions across KDE virtual desktops.
#
# Problem: Floorp's built-in session restore recovers all windows and tabs, but places
# all windows on the current desktop. When using multiple virtual desktops with dedicated
# browser windows per workspace, this breaks the layout.
#
# Solution: record which desktop each window lives on before killing Floorp, let Floorp
# restore its own session (preserving all tabs), then move the restored windows back to
# their original desktops.
#
# Key insight: Floorp restores windows in the same order they appear in its session store
# (recovery.jsonlz4), and wmctrl lists them in creation order. So the i-th window after
# restart corresponds to the i-th window before restart. This lets us match windows by
# position index instead of unreliable title matching.
#
# Window movement uses KWin scripting API (not wmctrl -t) to avoid _NET_WM_DESKTOP
# desync issues with KWin. See MEMORY.md for details on the desync problem.
#
# Usage:
#   restart-floorp.sh [--debug]
#       Restart Floorp in-place, preserving window positions in memory.
#       --debug: start with --start-debugger-server 6000
#
#   restart-floorp.sh --close [FILE]
#       Save window positions to FILE (default: ~/.floorp-desktops) and close Floorp.
#
#   restart-floorp.sh --restore FILE [--debug]
#       Start Floorp and restore window positions from FILE.
#       --debug: start with --start-debugger-server 6000
#
# Requirements: wmctrl, qdbus, KDE Plasma with KWin, Floorp with session restore enabled
#   (browser.startup.page = 3, browser.sessionstore.resume_from_crash = true)

set -euo pipefail

DEFAULT_SAVE_FILE="$HOME/.floorp-desktops"

# Move a window to a virtual desktop via KWin scripting API.
# Uses a temporary JS script loaded into KWin — the only reliable way to move windows
# without causing _NET_WM_DESKTOP desync (wmctrl -t conflicts with KWin's internal state).
# Args: $1 = hex window ID (from wmctrl), $2 = target desktop index (0-based, wmctrl style)
kwin_move_window() {
  local hex_wid="$1"
  local desktop_idx="$2"
  local dec_wid=$(( hex_wid ))
  local kwin_desktop=$(( desktop_idx + 1 ))  # KWin uses 1-based desktop numbering

  local script
  script=$(mktemp /tmp/kwin-move-XXXXXXXX.js)
  cat > "$script" << JSEOF
(function() {
  var clients = workspace.clientList();
  for (var i = 0; i < clients.length; i++) {
    if (clients[i].windowId === ${dec_wid}) {
      clients[i].desktop = ${kwin_desktop};
      return;
    }
  }
})();
JSEOF
  local script_name="floorp-restore-$$-$dec_wid"
  qdbus org.kde.KWin /Scripting unloadScript "$script_name" &>/dev/null || true
  qdbus org.kde.KWin /Scripting loadScript "$script" "$script_name" &>/dev/null
  qdbus org.kde.KWin /Scripting start &>/dev/null
  rm -f "$script"
}

# Save window positions to an array (desktops[]) and optionally to a file.
# Args: $1 = save file path (empty = don't save to file)
save_window_positions() {
  local save_file="${1:-}"

  if ! pgrep -x floorp >/dev/null 2>&1; then
    echo "Floorp is not running" >&2
    exit 1
  fi

  echo "Saving window layout..."

  desktops=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    desktop_idx=$(echo "$line" | awk '{print $2}')
    title=$(echo "$line" | sed 's/^[^ ]* *[^ ]* *[^ ]* *//' | sed 's/ — Ablaze Floorp$//')
    desktops+=("$desktop_idx")
    echo "  [${desktop_idx}] ${title:0:80}"
  done < <(DISPLAY=:0 wmctrl -l | grep "Ablaze Floorp")

  window_count=${#desktops[@]}
  if [[ $window_count -eq 0 ]]; then
    echo "No Floorp windows found" >&2
    exit 1
  fi

  if [[ -n "$save_file" ]]; then
    printf '%s\n' "${desktops[@]}" > "$save_file"
    echo "Saved $window_count window positions to $save_file"
  else
    echo "Saved $window_count window positions"
  fi
}

# Kill Floorp and wait for it to exit.
kill_floorp() {
  echo "Killing Floorp..."
  pkill -x floorp 2>/dev/null || true

  local deadline=$((SECONDS + 10))
  while (( SECONDS < deadline )); do
    pgrep -x floorp >/dev/null 2>&1 || break
    sleep 0.5
  done

  if pgrep -x floorp >/dev/null 2>&1; then
    pkill -9 -x floorp 2>/dev/null || true
    sleep 1
  fi

  echo "Floorp stopped"
}

# Start Floorp with optional extra args.
# Args: $@ = extra floorp arguments
start_floorp() {
  echo "Starting Floorp..."
  DISPLAY=:0 floorp "$@" &>/dev/null &
  disown
}

# Wait for N windows to appear and move them to saved desktops.
# Args: $1 = window count, $2..N = desktop indices
restore_window_positions() {
  local window_count="$1"
  shift
  local saved_desktops=("$@")

  echo "Waiting for $window_count windows..."

  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    local current_count
    current_count=$(DISPLAY=:0 wmctrl -l 2>/dev/null | grep "Ablaze Floorp" | grep -cv "^[^ ]* *[^ ]* *[^ ]* *Ablaze Floorp$" || true)
    if (( current_count >= window_count )); then
      break
    fi
    sleep 0.5
  done

  sleep 2

  echo "Moving windows to saved desktops..."

  local i=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if (( i >= window_count )); then
      break
    fi

    local wid current title target
    wid=$(echo "$line" | awk '{print $1}')
    current=$(echo "$line" | awk '{print $2}')
    title=$(echo "$line" | sed 's/^[^ ]* *[^ ]* *[^ ]* *//' | sed 's/ — Ablaze Floorp$//')

    # Skip service windows with no loaded content (e.g. blank window opened by --start-debugger-server)
    if [[ "$title" == "Ablaze Floorp" ]]; then
      echo "  (skip blank window)"
      continue
    fi

    target="${saved_desktops[$i]}"

    if [[ "$current" != "$target" ]]; then
      kwin_move_window "$wid" "$target"
      echo "  ${current}→${target} ${title:0:70}"
    fi
    (( i++ )) || true
  done < <(DISPLAY=:0 wmctrl -l | grep "Ablaze Floorp")

  echo "Done: moved $i windows"
}

# ── Main ──

mode="${1:-}"

case "$mode" in
  --close)
    save_file="${2:-$DEFAULT_SAVE_FILE}"
    save_window_positions "$save_file"
    kill_floorp
    ;;

  --restore)
    restore_file="${2:-}"
    if [[ -z "$restore_file" ]]; then
      echo "Usage: $0 --restore FILE [--debug]" >&2
      exit 1
    fi
    if [[ ! -f "$restore_file" ]]; then
      echo "Save file not found: $restore_file" >&2
      exit 1
    fi

    saved_desktops=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      saved_desktops+=("$line")
    done < "$restore_file"
    window_count=${#saved_desktops[@]}
    echo "Loaded $window_count window positions from $restore_file"

    floorp_extra_args=()
    if [[ "${3:-}" == "--debug" ]]; then
      floorp_extra_args=(--start-debugger-server 6000)
      echo "  (debug mode: --start-debugger-server 6000)"
    fi

    start_floorp "${floorp_extra_args[@]}"
    restore_window_positions "$window_count" "${saved_desktops[@]}"
    ;;

  --debug|"")
    desktops=()
    window_count=0
    save_window_positions ""
    kill_floorp

    floorp_extra_args=()
    if [[ "$mode" == "--debug" ]]; then
      floorp_extra_args=(--start-debugger-server 6000)
      echo "  (debug mode: --start-debugger-server 6000)"
    fi

    start_floorp "${floorp_extra_args[@]}"
    restore_window_positions "$window_count" "${desktops[@]}"
    ;;

  *)
    echo "Usage:" >&2
    echo "  $0 [--debug]                    restart, preserving window positions" >&2
    echo "  $0 --close [FILE]               save positions to FILE and close" >&2
    echo "  $0 --restore FILE [--debug]     start and restore positions from FILE" >&2
    exit 1
    ;;
esac
