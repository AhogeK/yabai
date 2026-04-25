# Upstream Sync Report

**Date**: 2026-04-26
**Range**: `7c4c5ba` → `f51e4b5` (30 commits)
**Upstream**: https://github.com/asmvik/yabai
**Our Version**: 7.1.25 (based on our 7.1.21 + upstream changes)

---

## Summary

Synced 30 upstream commits covering 7 major issue groups. All commits cherry-picked individually with version numbers preserved at our base (7.1.21 → 7.1.25).

---

## Commit Details (chronological, oldest first)

### #2780 — Space --focus with SIP enabled (5 commits)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `7c4c5ba` | implement space --focus with SIP enabled | `space_manager.c` (+53), `CHANGELOG.md`, `doc/yabai.1` | New feature: enables `space --focus` command to work when SIP is enabled, using a workaround that bypasses the need for scripting addition injection |
| `c26845f` | cleanup space --focus | `space_manager.c` (+11/-27) | Refactors initial implementation, reduces code size |
| `701d36b` | cleanup space --focus | `space_manager.c` (+20/-9) | Further refactoring of space focus logic |
| `770df04` | cleanup space --focus | `space_manager.c` (+3) | Minor cleanup |
| `c35b281` | cleanup space --focus | `space_manager.c` (+1/-1) | Final cleanup |

**Key change**: Introduces `space_manager_focus_space_with_sip()` function that uses `CGSDefaultConnection` and `SLSMoveSpacesToDisplay` to move windows between spaces without requiring scripting addition.

---

### #2781 — Bypass space switch animation (6 commits)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `b0959bb` | bypass space switch animation on cmd+tab with SIP enabled | `display.c`, `process_manager.c/h` (+74), `space.c`, `space_manager.c/h` | Adds `process_manager_set_front_process_option()` to disable space switch animation when using cmd+tab or clicking Dock items |
| `ccbe8bd` | improvements to removal of native window focus space animations | 11 files (+61/-11) | Extends animation bypass to more scenarios, adds `skip_window_focus_animation` config option, updates documentation |
| `5139390` | prevent ffm from triggering inside a space switching gesture | `event_loop.c`, `mouse_handler.c/h` (+30/-2) | Adds gesture detection to prevent focus-follows-mouse from triggering during space switching |
| `53a00b1` | cleanup | `application.c`, `event_loop.c`, `process_manager.c/h` (+20/-19) | Refactors process manager and event loop code |
| `a45de6f` | improve case 1. | `event_loop.c`, `mission_control.c`, `yabai.c` (+11/-2) | Improves Mission Control detection logic |
| `55d180c` | improve case 1. | `event_loop.c` (+1/-1) | Minor fix to event handling |

**Key change**: Introduces `CGSConnectionSetLocalEventTap` and `CGSMoveSpacesToDisplay` based animation bypass, plus `skip_window_focus_animation` config option in `yabairc`.

---

### #2217 — FFM window id reset / stale menu (2 commits)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `e5c710d` | stale menu closed events should not disable focus follows mouse | `event_loop.c` (+3/-4) | Fixes bug where closing stale menus would incorrectly disable FFM |
| `3a4e5a9` | properly reset ffm window id upon window close | `event_loop.c` (+2) | Resets FFM tracked window ID when windows close, preventing stale references |

---

### #2147 — Stub out function on modern macOS (1 commit)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `83d6055` | stub out function on modern macOS versions | `display_manager.c` (+25/-10) | Stubs out `display_manager_begin` function on modern macOS versions where the underlying API is no longer available, preventing crashes |

---

### #2694 — Autofocus delay + comment fix (2 commits)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `6ca1534` | slightly increase autofocus event delay | `window_manager.c` (+2/-2) | Increases autofocus event delay from previous value to improve reliability |
| `82b1ca7` | fix outdated comment | `window_manager.c` (+1/-1) | Updates comment to match current behavior |

---

### #2708 — Intel x64 scripting addition fix (2 commits)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `fdb0506` | fix broken scripting addition offset for macOS 15.7 Intel x64 | `osax/x64_payload.m` (+1/-1) | Fixes scripting addition offset for macOS 15.7 Intel, restoring window management functionality |
| `de6b29a` | bump sa version | `osax/common.h` (+1/-1) | Bumps scripting addition version to 2.1.29 |

---

### macOS 26.4 Intel x64 SA update (1 commit)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `f03b9a4` | update scripting addition for macOS 26.4 Intel x64 | `osax/x64_payload.m` (+4/-5), `osax/common.h` | Updates scripting addition patterns for macOS 26.4 Intel x64 |

---

### Intel support documentation (1 commit)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `f2e78d4` | update macOS intel support | `README.md` (+1/-1) | Updates README to reflect Intel macOS support |

---

### README update (1 commit)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `0d6a862` | update | `README.md` (+4/-4) | General README updates |

---

### Cleanup (1 commit)

| Commit | Subject | Files | Impact |
|--------|---------|-------|--------|
| `dfb3a12` | cleanup | `window_manager.c` (+15/-3) | General cleanup of window manager code |

---

## Version Bumps (8 commits — skipped, using our versioning)

| Upstream Version | Our Version |
|-----------------|-------------|
| v7.1.19 | (our 7.1.19 already exists) |
| v7.1.20 | (our 7.1.20 already exists) |
| v7.1.21 × 3 | (our 7.1.21 already exists) |
| v7.1.22 | → 7.1.22 (empty commit, version kept) |
| v7.1.23 | → 7.1.23 (empty commit, version kept) |
| v7.1.24 | → 7.1.24 (empty commit, version kept) |
| **Final** | **7.1.25** (our version) |

---

## Conflict Resolution Summary

| File | Conflicts | Resolution |
|------|-----------|------------|
| `CHANGELOG.md` | Multiple | Kept our version entries, added upstream changes |
| `scripts/install.sh` | Version bumps | Kept our version numbering |
| `src/yabai.c` | Version bumps | Kept our version numbering |
| `doc/yabai.1` | Date fields | Kept our dates |
| `src/osax/common.h` | SA version | Resolved per-commit |

---

## Files Changed (cumulative)

| File | Commits Touching |
|------|-----------------|
| `CHANGELOG.md` | 12 |
| `src/space_manager.c` | 6 |
| `src/event_loop.c` | 6 |
| `src/window_manager.c` | 3 |
| `src/process_manager.c/h` | 4 |
| `doc/yabai.1` | 2 |
| `src/osax/x64_payload.m` | 2 |
| `src/osax/common.h` | 3 |
| `src/display_manager.c` | 1 |
| `src/display.c` | 1 |
| `src/space.c` | 1 |
| `src/mouse_handler.c/h` | 2 |
| `src/application.c` | 2 |
| `src/mission_control.c` | 1 |
| `src/yabai.c` | 1 |
| `README.md` | 2 |
| `scripts/install.sh` | 8 |
| `examples/yabairc` | 1 |
| `doc/yabai.asciidoc` | 1 |
