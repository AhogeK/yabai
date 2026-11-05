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
