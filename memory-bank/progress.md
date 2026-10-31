# Progress - yabai

## Current Phase: 7.2.41 off recovery (2026-11-01)

- **Root cause**: `fast_window_switch off` blocked the event-loop in `dock_set_auto_swoosh -> safe_exec -> wait4`; the config command never returned and native switching could not be restored.
- **Fix**: Dock restart wait moved to a detached thread; off writes `workspaces-auto-swoosh=true` and returns immediately. Wait for Dock relaunch before expecting native Cmd+Tab.
- **Verification**: build 0 warning; `make -C tests all` 6/6; runtime `off` validation pending user restart.
- **Version**: 7.2.41; uncommitted.
### Phase 69: single window-focus path (2026-11-01)
- `window --focus` already does space focus + visibility wait + exact window focus; removed redundant `space --focus` race. Manual hidden IntelliJ: 0.09–0.12s, wid 15149, space 8.
- Real Cmd+Tab 8 samples: cmux↔IntelliJ, `latency_ms` 301–357ms, `focus_ms` 39–93ms, no failures; AXFocusedWindow=15149, target correct.
- Remaining 240–282ms precedes the script; script cannot reach <200ms.
### Phase 68: latency options after lock (2026-10-31)
- Measured single landing 246–408ms; script 60–70ms; only pre-activation Cmd+Tab takeover could go below 200ms.
- Decision: not a script optimization; keep current signal/C approach.
### Phase 67: single-flight lock (2026-10-31)
- One Cmd+Tab emitted paired `space-only`/`window-focus`; two invocations passed input state.
- Added `/tmp/yabai_app_fast_land.lock`; post-lock samples single, with `skip-loop` for self events.
### Phase 66: space-only experiment (2026-10-31)
- Removed `window --focus` temporarily; latency 203–273ms but multi-window target was wrong; reverted.
### Phase 65: restore pre-C script path (2026-10-31)
- Restored signal script; `fast_window_switch on`, auto-swoosh 0; `date +%s%N`, no `sleep 0.02`; ~70ms overhead.
### Phase 64: two-desktop loop rollback (2026-10-31)
- 7.2.40 event-counter gate failed to distinguish self-triggered events; runtime switched off and native restored. This drove the new any-input gate.
### Phase 63: input gate (2026-10-31)
- Replaced HID-idle logic with key/mouse counters; still missed gestures and consumed credit before validation.
### Phase 62: visible window on another display (2026-10-31)
- C path focused owning display before window; fixed Cmd+Tab no-op when app already visible on another display.
### Phase 61: C fast-focus single command (2026-10-31)
- Signal action becomes one `yabai -m window --fast-focus <pid>`; C owns config, gate, target, space, window focus.
- Removed jq/ioreg/perl; runtime deploy pending.
### Phase 60: config + signal architecture (2026-10-31)
- `fast_window_switch` config + signal action; `on` writes auto-swoosh=false and restarts Dock; `off` restores true; Dock restart backgrounded to avoid event-loop wait.
### Phase 58: unify native window focus (2026-10-31)
- Removed old `application_fast_land`, probe/gate globals, type-1202 timestamp, and `fast_window_switch`; reverted later by plan 1.
- Current state supersedes this removal: config + C fast-focus restored.
### Phase 57: native switch investigation (2026-10-31)
- `workspaces-auto-swoosh=false` prevented native Cmd+Tab space switching; auto-swoosh true + fast off was stable.
- 7.2.34 changed deploy default to true; 7.2.36 stopped writing it; current fix restores true.
### Phase 56: AX focus false negative (2026-10-31)
- Window `AXFocused` can be false while system `AXFocusedUIElement` maps to the window; system-level `_AXUIElementGetWindow` used.
### Phase 55: probe/refocus (2026-10-31)
- 300ms AX probe and conditional refocus; later removed with the fast-landing rewrite.
### Phase 54: SLSSpaceSetFrontPSN removal (2026-10-31)
- Removed pre-switch `SLSSpaceSetFrontPSN`; direct `space --focus` + wait + window raise is the valid order.
### Phase 53: target-only visibility (2026-10-31)
- Only the selected target window determines whether to switch; other same-app windows/dialogs must not suppress landing.
### Phase 52: standard-window visibility (2026-10-31)
- AXDialog/floating windows were counted as visible; restrict to standard windows.
### Phase 51: no-input skip (2026-10-31)
- Moved gate to entry; no new keyboard/mouse/gesture after previous landing → skip without clearing state, preventing suppress/allow alternation.
### Phase 50: gesture intent (2026-10-31)
- Gesture-driven space switches lack key/mouse down; added gesture timestamp to intent.
### Phase 49: HID idle (2026-10-31)
- Hardware idle used to distinguish user input from synthesized events; later replaced by event counters, now any-input timestamp.
### Phase 48: bounce guard false positive (2026-10-31)
- 7.2.23 suppressed real switches after >1.5s; switched to user-input timestamp.
### Phase 47: runaway loop (2026-10-31)
- 2311 fast switches in one storm; added reverse-switch guard; later replaced by input-gated single-flight logic.

## Historical summary

- Phase 46: Dock animation investigation; WindowServer transition unresolved; root LLDB attach banned after 18:48 incident.
- Phase 44–45: 7.2.18 space focus/IOHID; REA/Ghidra v3.
- Phase 40–43: fullscreen workaround retired; window focus fast landing 7.2.14.
- Phase 39–1: macOS 26/27 SA space creation, patterns, space identity fix 7.2.6; details in `archive/` and `domains/space-management/`.

## Key findings

- `window --focus` is the safe primitive: it switches hidden spaces, waits for visibility, and focuses the exact window.
- App activation before `application_front_switched` dominates perceived latency; post-signal code cannot remove it.
- Multi-window correctness requires `AXFocusedWindow`/`has-focus` precedence, never table order.
- Any-input gate must include gestures; event counters alone are insufficient.
- C fast-focus must be the only landing path if it is documented; otherwise remove it and the config.

## Memory Bank status

| File | Lines | Limit |
|---|---:|---:|
| activeContext.md | 60 | 150 |
| progress.md | 84 | 100 |
| systemPatterns.md | 63 | 80 |
| techContext.md | 73 | 80 |
| projectbrief.md | 22 | 50 |
