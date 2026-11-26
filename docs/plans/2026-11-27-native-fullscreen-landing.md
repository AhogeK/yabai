# Plan: Native fullscreen landing in fast landing

Date: 2026-11-27 · Status: completed (7.2.45)

## Objective

Make Cmd+Tab land on a native fullscreen window (chiaki) that lives on its own Space, without regressing the pid-only design of 7.2.44.

## Root cause

- `application_front_switched` carries the app pid; the script resolves its focused window (wid 20178, space 3).
- `yabai -m window --focus 20178` returns `could not locate window.` (rc=1) for `is-native-fullscreen=true`; the script logged `land-failed` and nothing switched.
- `yabai -m space --focus 3` works and brings the fullscreen app frontmost (`front=chiaki`, verified with osascript).

## Change

- `examples/app_fast_land.sh`: read `."is-native-fullscreen"` from the window query and pass it into `land_window()`.
- Fullscreen target: if its space is already current, log `skip-fullscreen-active` (repeated event); otherwise `yabai -m space --focus <space>` and log `land-ok` / `land-failed` with `fullscreen=1`.
- Hidden-window, minimized and cross-display paths are unchanged.

## Verification

- Live: `YABAI_PROCESS_ID=10775 ./app_fast_land.sh` → space 3, `front=chiaki`, `land-ok fullscreen=1`; two repeats → `skip-fullscreen-active`; environment restored to space 2 / wid 193.
- `./tests/script/fast_land_test.sh` 29/29 (three new fullscreen cases); `make -C tests all` 6/6; `make BUILD_PATH=/tmp/yabai-7245-build` 0 warnings.

## Files

- `examples/app_fast_land.sh`, `tests/script/fast_land_test.sh`
- `README.md`, `doc/yabai.asciidoc`, `doc/yabai.1`
- `src/yabai.c`, `scripts/install.sh`, `CHANGELOG.md`
- `AGENTS.md` (R22), `memory-bank/activeContext.md`, `memory-bank/progress.md`, `memory-bank/domains/space-management/scenarios.md`

## Commits

- ai-base: `0c177e6` feature, `cac8d57` docs, `a1197bf` version, `d7099ca` man, `cb317db` AI notes.
- dev: `6b552a5`, `f618ce2`, `9ef6969`, `5f72c7b`.
- master: `81045dd`, `9dac429`, `171a7d7`, `3b3d42e`.

## Outcome and follow-ups

- The fix lives entirely in the script; no C change, so the installed 7.2.43 binary needs no redeploy for this behaviour.
- Pending: the operator's own Cmd+Tab to chiaki after the fix. The manual run proved the path; only the key press is unobserved.
- 7.2.44's pid-only rule stands: `window_focused` still takes no action.
