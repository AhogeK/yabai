# Plan: Unify app and window switching on native window focus

Date: 2026-10-31 · Status: superseded by `2026-11-01-code-review-fixes.md` (the reviewed tree keeps the C fast-focus path)

## Objective

Remove the app-specific `APPLICATION_FRONT_SWITCHED` fast-landing path so Cmd+Tab and Opt+Shift+Tab both use the same native window-focus/Space-switch behavior. Keep `workspaces-auto-swoosh` enabled; remove `fast_window_switch` and its measurement code.

## Restore point

Tag: `checkpoint-pre-fast-landing-removal`
Stash snapshot of the 7.2.34 working tree. Restore with:

```bash
git stash apply checkpoint-pre-fast-landing-removal
```

Keep the stash and tag until the cleanup is verified.

## Affected files

| File | Change |
|---|---|
| `src/event_loop.c` | Remove `application_fast_land`, its `APPLICATION_FRONT_SWITCHED` call, probe code, gate globals, and the now-unused `_AXUIElementGetWindow` declaration |
| `src/space_manager.c` / `.h` | Remove `fast_window_switch` field and default |
| `src/message.c` | Remove `fast_window_switch` config command and print |
| `src/mission_control.c` | Remove the type-1202 timestamp if only used by the removed gate |
| `src/window_manager.h` | Remove `window_manager_should_refocus_target` |
| `tests/src/tests.m` | Remove the refocus truth-table test |
| `src/yabai.c` / `scripts/install.sh` | Bump to 7.2.35 |
| `CHANGELOG.md` | Add removal entry |
| `README.md` / `doc/yabai.asciidoc` / `doc/yabai.1` | Remove fast-landing docs; keep native auto-swoosh note |
| `memory-bank/activeContext.md` / `progress.md` | Record the unified native path |
| `.omp/report/yabai-fast-landing-cmd-tab-problem-report.md` | Final report for review |

## Steps

1. Remove the fast-landing function and call; keep `WINDOW_FOCUSED` and `skip_window_focus_animation` behavior unchanged.
2. Remove `fast_window_switch` from config, space manager, docs, tests.
3. Bump version and changelog.
4. Build with `-Wall -Wextra`; run `make -C tests all`.
5. Confirm no `application_fast_land` / `fast_window_switch` references remain.
6. Update memory and report.
7. User verifies Cmd+Tab and Opt+Shift+Tab both switch with the native animation.

## Success criteria

- `make` 0 warnings; tests pass.
- `grep -R fast_window_switch src tests README.md doc` returns no production references.
- No `application_fast_land` call remains.
- `make deploy` keeps `workspaces-auto-swoosh=true`.
- Cmd+Tab and Opt+Shift+Tab both use native Space switching; only the system animation remains.
