#!/usr/bin/env bash
#
# Integration test for examples/app_fast_land.sh.
#
# The real script runs against a stub `yabai` on PATH, so every branch is
# exercised without touching the window server: config gate, the ignored
# window_focused path, landing, display follow, minimized restore, lock
# contention and log rotation. Log and lock paths are redirected so the live
# files are never touched.
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
    export STUB_MODE=on
    displays 1 > "$STUB_DISPLAYS"
    unset YABAI_WINDOW_ID YABAI_PROCESS_ID
}

logged() {  # action names in order
    grep -o 'action=[a-z-]*' "$tmp/log" 2>/dev/null | cut -d= -f2 | tr '\n' ' ' | sed 's/ $//'
}

invoke() {
    YABAI_FAST_LAND_LOG="$tmp/log" YABAI_FAST_LAND_LOCK="$tmp/lock" "$SCRIPT"
}

# 1. Disabled: the config gate stops everything.
reset; export STUB_MODE=off
printf '[%s]\n' "$(window 42 3 1 false false false)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'disabled: no cli action' '' "$(cat "$STUB_ACTIONS")"
check 'disabled: no log line' '' "$(logged)"

# 2. window_focused for a visible window: logged, never acted on.
reset
YABAI_WINDOW_ID=42 invoke
check 'wid visible: log' 'skip-window-event' "$(logged)"
check 'wid visible: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 3. window_focused for a hidden window: still not acted on. This is the
#    artifact that used to pull focus back to the old Space.
reset
window 42 3 1 false false false > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'wid hidden: log' 'skip-window-event' "$(logged)"
check 'wid hidden: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 4. window_focused for a minimized window: not acted on either.
reset
window 42 3 1 false true false > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'wid minimized: log' 'skip-window-event' "$(logged)"
check 'wid minimized: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 5. window_focused for a window on another display: no display follow.
reset
window 42 3 2 true false false > "$STUB_WINDOW"
YABAI_WINDOW_ID=42 invoke
check 'wid other display: log' 'skip-window-event' "$(logged)"
check 'wid other display: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 6. App-front for a hidden window: land.
reset
printf '[%s]\n' "$(window 42 3 1 false false false)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'pid hidden: log' 'land land-ok' "$(logged)"
check 'pid hidden: cli action' '-m window --focus 42' "$(cat "$STUB_ACTIONS")"

# 7. App-front for a minimized window: restore, then land.
reset
printf '[%s]\n' "$(window 42 3 1 false true false)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'pid minimized: log' 'deminimize land land-ok' "$(logged)"
check 'pid minimized: cli actions' '-m window --deminimize 42
-m window --focus 42' "$(cat "$STUB_ACTIONS")"

# 8. App-front for a visible window on another display: follow the display.
reset
printf '[%s]\n' "$(window 42 3 2 true false false)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'pid other display: log' 'focus-display' "$(logged)"
check 'pid other display: cli action' '-m display --focus 2' "$(cat "$STUB_ACTIONS")"

# 9. App-front for a visible window on the active display: no-op.
reset
printf '[%s]\n' "$(window 42 1 1 true false false)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'pid visible: log' 'skip-visible' "$(logged)"
check 'pid visible: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 10. App-front resolves the application's focused window first.
reset
printf '[%s,%s]\n' "$(window 41 3 1 false false false)" "$(window 42 1 1 true false true)" > "$STUB_WINDOWS"
YABAI_PROCESS_ID=77 invoke
check 'pid focused window: log' 'skip-visible' "$(logged)"
check 'pid focused window: no cli action' '' "$(cat "$STUB_ACTIONS")"

# 11. A live foreign lock makes the duplicate give up instead of acting.
reset
printf '[%s]\n' "$(window 42 3 1 false false false)" > "$STUB_WINDOWS"
mkdir -p "$tmp/lock"
printf '999999\n' > "$tmp/lock/pid"
YABAI_PROCESS_ID=77 invoke
check 'lock held: no cli action' '' "$(cat "$STUB_ACTIONS")"
check 'lock held: foreign lock preserved' '999999' "$(cat "$tmp/lock/pid" 2>/dev/null || printf missing)"
rm -rf "$tmp/lock"

# 12. The log is bounded even when only window events arrive.
reset
for _ in $(seq 8000); do printf '1700000000 wid=1 space=1 action=padding\n'; done > "$tmp/log"
YABAI_WINDOW_ID=42 invoke
lines=$(wc -l < "$tmp/log" | tr -d ' ')
check 'rotation: bounded line count' 'yes' "$([[ "$lines" -le 210 ]] && echo yes || echo "no:${lines}")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
