#!/usr/bin/env bash
#
# Opt-in fast landing for yabai.
#
# Registered for application_front_switched, which carries YABAI_PROCESS_ID.
#
# Only that signal acts. window_focused is logged and ignored: yabai raises it
# for focus changes nobody asked for (the app re-asserting a window after a
# Space switch, or the window on the display we just left), and acting on it
# lands back on the old window. Measured on macOS 27.2: two windows of one app
# ping-ponged across Spaces about 4 times per second, and two Chrome windows
# across displays about 2 times per second.
#
# Lands only when the target window is not visible: its Space is hidden, or it
# is minimized. A visible window on the active display is a no-op, so a focus
# event raised by our own landing cannot revert it.
#
# Log and lock paths can be overridden for the test harness; the defaults are
# what the installed signal uses.
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

# Which signal produced this invocation.
src="none"
[[ -n "$wid" ]] && src="wid"
[[ -n "$pid" ]] && src="pid"

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

# A window event is a system artifact, not a request: log it and stop before
# touching any window. This is what keeps the Space and display loops from
# starting.
if [[ "$src" != "pid" ]]; then
    printf '%s src=wid wid=%s action=skip-window-event\n' "$now_s" "$wid" >> "$log"
    exit 0
fi

#
# Resolve the target from the application: its focused window, then its first
# standard window.
#
target="$(yabai -m query --windows 2>/dev/null | jq -c --argjson pid "$pid" '
    [.[] | select(.pid == $pid)] as $w
    | ($w | map(select(."has-focus" == true))[0])
      // ($w | map(select(.role == "AXWindow" and .subrole == "AXStandardWindow"))[0])
      // $w[0]
      // empty
' || true)"

[[ -n "$target" ]] || exit 0

# One jq call for all fields: a process per field costs ~4.6ms each.
fields="$(jq -r '[.id, .space, .display, ."is-visible", ."is-minimized"] | @tsv' <<<"$target")" || exit 0
IFS=$'\t' read -r wid space display visible minimized <<<"$fields"

log_line() {  # wid space action [extra-field]
    local extra=${4:+$4 }
    printf '%s src=%s wid=%s space=%s %saction=%s\n' "$now_s" "$src" "$1" "$2" "$extra" "$3" >> "$log"
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

# Visible: follow the display when the window lives on another one.
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
