> 冷数据归档（R12）。仅供回溯，不再更新。
> 来源：memory-bank/progress.md（2026-10-31 阶段，2026-11-06 归档）

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
