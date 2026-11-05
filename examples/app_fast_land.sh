#!/usr/bin/env bash
#
# Opt-in fast landing for yabai.
#
# Registered for two events:
#   application_front_switched -> YABAI_PROCESS_ID (cross-app Cmd+Tab)
#   window_focused             -> YABAI_WINDOW_ID   (same-app window switch)
#
# Both are required: application_front_switched only pushes window_focused when
# it can resolve AXFocusedWindow, so it is the only signal left when that
# resolution fails; window_focused is the only one that fires for same-app
# window switches.
#
# Lands only when the target window is not visible: its Space is hidden, or it
# is minimized. A visible window on the active display is a no-op, so a focus
# event raised by our own landing cannot revert it.
#
# Log and lock paths can be overridden for the test harness; the defaults are
# what the installed signals use.
#
set -euo pipefail

log="${YABAI_FAST_LAND_LOG:-/tmp/yabai_app_fast_land.log}"
lock="${YABAI_FAST_LAND_LOCK:-/tmp/yabai_app_fast_land.lock}"

# bash has no builtin clock: read it once and reuse it for every log line.
now_s="$(date +%s)"

mode="$(yabai -m config fast_window_switch 2>/dev/null || printf off)"
[[ "$mode" == "on" ]] || exit 0

wid="${YABAI_WINDOW_ID:-}"
pid="${YABAI_PROCESS_ID:-}"

#
# One landing emits more than one event (app-front, plus the window_focused it
# pushes, plus the AX observer's follow-up). Serialize invocations so the
# self-generated follow-up cannot switch back, while still letting a rapid
# second Cmd+Tab wait for the first landing instead of being dropped.
#
# The lock carries the owner pid: stale cleanup can replace the directory, and
# a slow holder must not then delete its successor's lock on exit.
#
if [[ -d "$lock" ]]; then
    lock_mtime="$(stat -f %m "$lock" 2>/dev/null || printf 0)"
    (( now_s - lock_mtime <= 2 )) || rm -rf "$lock" 2>/dev/null || true
fi

locked=0
# 30 x 20ms = 600ms, well above a landing (~160ms), so a slow animation cannot
# cost the user a keypress. Most invocations acquire on the first attempt.
for _ in {1..30}; do
    if mkdir "$lock" 2>/dev/null; then
        printf '%s\n' "$$" > "$lock/pid"
        locked=1
        break
    fi
    sleep 0.02
done
[[ "$locked" == 1 ]] || exit 0

release_lock() {
    if [[ -f "$lock/pid" && "$(<"$lock/pid")" == "$$" ]]; then
        rm -rf "$lock"
    fi
}
trap release_lock EXIT

# The log is appended by every branch, so it is bounded once per invocation
# rather than only on landing paths: a skip-only workload grows it too.
rotate_log() {
    [[ -f "$log" ]] || return 0
    (( $(stat -f%z "$log" 2>/dev/null || printf 0) > 262144 )) || return 0
    if tail -n 200 "$log" > "$log.$$" 2>/dev/null; then
        mv "$log.$$" "$log"
    else
        rm -f "$log.$$"
    fi
}
rotate_log

#
# Resolve the target: the signaled window when present, otherwise the
# application's focused window, then its first standard window.
#
target=""
if [[ -n "$wid" ]]; then
    target="$(yabai -m query --windows --window "$wid" 2>/dev/null || true)"
elif [[ -n "$pid" ]]; then
    target="$(yabai -m query --windows 2>/dev/null | jq -c --argjson pid "$pid" '
        [.[] | select(.pid == $pid)] as $w
        | ($w | map(select(."has-focus" == true))[0])
          // ($w | map(select(.role == "AXWindow" and .subrole == "AXStandardWindow"))[0])
          // $w[0]
          // empty
    ' || true)"
fi

[[ -n "$target" ]] || exit 0

# One jq call for all fields: a process per field costs ~4.6ms each, and the
# duplicate-event path is dominated by these forks.
fields="$(jq -r '[.id, .space, .display, ."is-visible", ."is-minimized"] | @tsv' <<<"$target")" || exit 0
IFS=$'\t' read -r wid space display visible minimized <<<"$fields"

log_line() {  # wid space action [extra-field]
    local extra=${4:+$4 }
    printf '%s wid=%s space=%s %saction=%s\n' "$now_s" "$1" "$2" "$extra" "$3" >> "$log"
}

land_window() {
    log_line "$wid" "$space" land
    if yabai -m window --focus "$wid" >/dev/null 2>&1; then
        log_line "$wid" "$space" land-ok
    else
        log_line "$wid" "$space" land-failed
    fi
}

# A minimized window is never visible: restore it, then land on it.
if [[ "$minimized" == "true" ]]; then
    log_line "$wid" "$space" deminimize
    yabai -m window --deminimize "$wid" >/dev/null 2>&1 || true
    land_window
    exit 0
fi

# Visible: follow the display when the window lives on another one. This check
# is not skipped for a focused window: right after a display switch the daemon
# can still report the previous display as focused for up to ~0.4s, measured on
# macOS 27.2, and an early exit would then swallow the follow.
if [[ "$visible" == "true" ]]; then
    active_display="$(yabai -m query --displays 2>/dev/null | jq -r '[.[] | select(."has-focus" == true) | .index][0] // empty' || true)"
    if [[ -z "$active_display" || "$display" == "$active_display" ]]; then
        log_line "$wid" "$space" skip-visible
        exit 0
    fi
    log_line "$wid" "$space" focus-display "display=$display"
    yabai -m display --focus "$display" >/dev/null 2>&1 || true
    exit 0
fi

# Hidden Space: `window --focus` switches the Space itself, waits for it to
# become visible, and raises the window; no separate space --focus call.
land_window
