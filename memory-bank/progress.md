# Progress - yabai

## Current Phase: 7.2.43 — 来回落焦修复（2026-11-06，已发布）
- **根因**：落位切 Space 后 App 重上报另一个窗口，`window_focused` 形成乒乓（IntelliJ 两个窗口两个 Space，约 4 次落位/秒）。
- **修复**：同一 pid、不同 wid、落位后 1 秒内的 `window_focused` 记 `skip-app-reassert` 并退出；`application_front_switched` 不过滤。
- **验证**：受控复现 17 行/2 秒 → 修复后同类事件 1 行即止，3 秒静置无新增；`tests/script/fast_land_test.sh` 27/27。
- **待验证**：真实 opt+shift+n 流程（含 destroy_empty_spaces 步骤）。
- **发布**：ai-base `bf5e3bb`（功能）/ `c8a18c1`（版本）；dev `97fff35` / `811067d`；master `6f45d08` / `d843b5c`；三支已推送。

## Current Phase: 7.2.42 — 脚本 + 双 signal（2026-11-06，已发布）
- **内容**：fast landing 从 C 退回脚本 `examples/app_fast_land.sh`；双 signal + 单飞锁；重复事件 94→40ms，锁 600ms + owner pid，日志全路径轮转。
- **验证**：`tests/script/fast_land_test.sh` 21/21；`make` 0 warning；`make -C tests all` 6/6；手动分支矩阵全过。
- **审查后修正**：删除“已聚焦且可见即退出”分支（实测切换显示器后存在约 0.4s 的焦点归属滞后，会吞掉 display 跟随）。
- **待验证**：真实 Cmd+Tab 按键。详见 `activeContext.md`。

## Phase: Cmd+Tab 回归回退（2026-11-01）
- **根因**：C `--fast-focus-window` 只认 signal wid / AX 焦点窗口；`application_front_switched` 在 AX 解析失败时不发 `window_focused`；auto-swoosh 已关 → 无路径切 desktop。
- **处置**：源码逻辑回 7.2.41，改由脚本承担；推翻 Phase 68/69 的“C 为唯一落位实现”。

## Current Phase: 7.2.41 off recovery (2026-11-01)

- **Root cause**: `fast_window_switch off` blocked the event-loop in `dock_set_auto_swoosh -> safe_exec -> wait4`; the config command never returned and native switching could not be restored.
- **Fix**: Dock restart wait moved to a detached thread; off writes `workspaces-auto-swoosh=true` and returns immediately. Wait for Dock relaunch before expecting native Cmd+Tab.
- **Verification**: build 0 warning; `make -C tests all` 6/6; runtime `off` validation pending user restart.
- **Version**: 7.2.41; released/pushed; runtime off-state validation still pending.
- **Release commits**: ai-base `d8847a3`/`04526c0`/`af7c29c`/`82f79da`/`9b07b38` + AI `0af9f9f`; dev `d0c29b9`/`139fea7`/`0465ae6`/`6501d15`/`b24ea88`; master `a87917e`/`df7d97d`/`51b5c8f`/`2a35595`/`2f8cc15`; all pushed.
- **Runtime**: off-state validation still pending user `make deploy`/restart.
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
| activeContext.md | 61 | 150 |
| progress.md | 86 | 100 |
| systemPatterns.md | 63 | 80 |
| techContext.md | 73 | 80 |
| projectbrief.md | 22 | 50 |
