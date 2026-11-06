#!/usr/bin/env bash
#
# Integration test for examples/app_fast_land.sh.
#
# The real script runs against a stub `yabai` on PATH, so every branch is
# exercised without touching the window server: config gate, target
# resolution, visibility decisions, landing, display follow, lock contention
# and log rotation. Log and lock paths are redirected so the live files are
# never touched.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/examples/app_fast_land.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/yabai-fast-land-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub" "$tmp/fixtures"

cat > "$stub/yabai" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    "-m config fast_window_switch") printf '%s\n' "${STUB_MODE:-on}" ;;
    "-m query --windows --window "*) cat "$STUB_WINDOW" ;;
    "-m query --windows") cat "$STUB_WINDOWS" ;;
    "-m query --displays") cat "$STUB_DISPLAYS" ;;
    "-m window --focus "*) printf '%s\n' "$*" >> "$STUB_ACTIONS" ;;
    "-m window --deminimize "*) printf '%s\n' "$*" >> "$STUB_ACTIONS" ;;
    "-m display --focus "*) printf '%s\n' "$*" >> "$STUB_ACTIONS" ;;
    *) exit 0 ;;
esac
STUB
chmod +x "$stub/yabai"
export PATH="$stub:$PATH"

export STUB_ACTIONS="$tmp/actions"
export STUB_WINDOW="$tmp/fixtures/window.json"
export STUB_WINDOWS="$tmp/fixtures/windows.json"
export STUB_DISPLAYS="$tmp/fixtures/displays.json"

pass=0
fail=0

check() {   # description, expected, actual
    if [[ "$2" == "$3" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"
    fi
}

window() {  # id space display visible minimized focused [pid]
    local p=${7:-77}
    printf '{"id":%s,"pid":%s,"space":%s,"display":%s,"role":"AXWindow","subrole":"AXStandardWindow","is-visible":%s,"is-minimized":%s,"has-focus":%s}\n' \
        "$1" "$p" "$2" "$3" "$4" "$5" "$6"
}

displays() {  # index of the active display
    local one=false two=false
    [[ "$1" == 1 ]] && one=true
    [[ "$1" == 2 ]] && two=true
    printf '[{"index":1,"has-focus":%s},{"index":2,"has-focus":%s}]\n' "$one" "$two"
}

reset() {
    : > "$STUB_ACTIONS"
    : > "$tmp/log"
    rm -f "$tmp/state"
    export STUB_MODE=on
    displays 1 > "$STUB_DISPLAYS"
    unset YABAI_WINDOW_ID YABAI_PROCESS_ID
}

logged() {  # action names in order
    grep -o 'action=[a-z-]*' "$tmp/log" 2>/dev/null | cut -d= -f2 | tr '\n' ' ' | sed 's/ $//'
}

invoke() {
    YABAI_FAST_LAND_LOG="$tmp/log" YABAI_FAST_LAND_LOCK="$tmp/lock" \
    YABAI_FAST_LAND_STATE="$tmp/state" "$SCRIPT"
}

# 1. Disabled: the config gate must stop everything before any query.
reset; export STUB_MODE=off
window 42 1 1 true false true > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'disabled: no cli action' '' "$(cat "$STUB_ACTIONS")"
check 'disabled: no log line' '' "$(logged)"

# 2. Focused and visible on the active display: no-op.
reset
window 42 1 1 true false true > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'focused+visible: log' 'skip-visible' "$(logged)"
check 'focused+visible: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 3. Hidden Space: land.
reset
window 42 3 1 false false false > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'hidden: log' 'land land-ok' "$(logged)"
check 'hidden: cli action' '-m window --focus 42' "$(cat "$STUB_ACTIONS")"

# 4. Minimized: restore, then land.
reset
window 42 3 1 false true false > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'minimized: log' 'deminimize land land-ok' "$(logged)"
check 'minimized: cli actions' '-m window --deminimize 42
-m window --focus 42' "$(cat "$STUB_ACTIONS")"

# 5. Visible on another display: follow the display, do not switch Spaces.
reset
window 42 3 2 true false false > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'other display: log' 'focus-display' "$(logged)"
check 'other display: cli action' '-m display --focus 2' "$(cat "$STUB_ACTIONS")"

# 6. Visible on the active display but not focused: no-op.
reset
window 42 1 1 true false false > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'visible: log' 'skip-visible' "$(logged)"
check 'visible: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 7. App-front signal: the application's focused window is used.
reset
printf '[%s,%s]\n' "$(window 41 3 1 false false false)" "$(window 42 1 1 true false true)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'pid focused window: log' 'skip-visible' "$(logged)"
check 'pid focused window: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 8. App-front signal without a focused window: first standard window is used.
reset
printf '[%s,%s]\n' "$(window 41 3 1 false false false)" "$(window 42 1 1 true false false)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'pid fallback window: log' 'land land-ok' "$(logged)"
check 'pid fallback window: cli action' '-m window --focus 41' "$(cat "$STUB_ACTIONS")"

# 9. Focused window on a non-active display: the display must still follow.
#    The daemon can report this state for ~0.4s after a display switch, so a
#    focused-window early exit is wrong here.
reset
window 42 3 2 true false true > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'focused on other display: log' 'focus-display' "$(logged)"
check 'focused on other display: cli action' '-m display --focus 2' "$(cat "$STUB_ACTIONS")"

# 10. A live foreign lock makes the duplicate give up instead of acting.
reset
window 42 3 1 false false false > "$STUB_WINDOW"
mkdir -p "$tmp/lock"
printf '999999\n' > "$tmp/lock/pid"
YABAI_WINDOW_ID=42 invoke
check 'lock held: no cli action' '' "$(cat "$STUB_ACTIONS")"
check 'lock held: foreign lock preserved' '999999' "$(cat "$tmp/lock/pid" 2>/dev/null || printf missing)"
rm -rf "$tmp/lock"

# 11. The log is bounded even on skip-only traffic.
reset
window 42 1 1 true false true > "$STUB_WINDOW"
for _ in $(seq 8000); do printf '1700000000 wid=1 space=1 action=padding\n'; done > "$tmp/log"
YABAI_WINDOW_ID=42 invoke
lines=$(wc -l < "$tmp/log" | tr -d ' ')
check 'rotation: bounded line count' 'yes' "$([[ "$lines" -le 210 ]] && echo yes || echo "no:${lines}")"

# 12. The app re-asserts its other window after our landing: not user intent,
#     must not land back (this is the cross-Space ping-pong).
reset
window 42 3 1 false false false 77 > "$STUB_WINDOW"
printf '%s 77 41\n' "$(date +%s)" > "$tmp/state"
YABAI_WINDOW_ID=42 invoke
check 'app re-assert: log' 'skip-app-reassert' "$(logged)"
check 'app re-assert: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 13. A different app right after a landing is real intent: land.
reset
window 42 3 1 false false false 88 > "$STUB_WINDOW"
printf '%s 77 41\n' "$(date +%s)" > "$tmp/state"
YABAI_WINDOW_ID=42 invoke
check 'other app after landing: log' 'land land-ok' "$(logged)"
check 'other app after landing: cli action' '-m window --focus 42' "$(cat "$STUB_ACTIONS")"

# 14. A state entry older than the filter window must not suppress anything.
reset
window 42 3 1 false false false 77 > "$STUB_WINDOW"
printf '%s 77 41\n' "$(( $(date +%s) - 5 ))" > "$tmp/state"
YABAI_WINDOW_ID=42 invoke
check 'stale state: log' 'land land-ok' "$(logged)"

# 15. application_front_switched is never filtered: rapid Cmd+Tab must land.
reset
printf '[%s]\n' "$(window 42 3 1 false false false 77)" > "$STUB_WINDOWS"
printf '%s 77 41\n' "$(date +%s)" > "$tmp/state"
YABAI_PROCESS_ID=77 invoke
check 'app-front not filtered: log' 'land land-ok' "$(logged)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
