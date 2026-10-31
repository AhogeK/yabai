# Plan: Config-gated fast window switch with signal action

Date: 2026-10-31 · Status: active; implementation corrections tracked in `2026-11-01-code-review-fixes.md`

## Objective

Keep `yabairc` declarative: a `yabai -m config` property and a `yabai -m signal`
registration only. Setting `fast_window_switch on` automatically writes
`com.apple.dock.workspaces-auto-swoosh=false` and restarts Dock when the value
changes; the signal action calls `yabai -m window --fast-focus <pid>`, and the
daemon owns landing state, input gating, target selection and focus.

## Affected Files

| File | Change |
|---|---|
| `src/space_manager.h` | Add `bool fast_window_switch` |
| `src/space_manager.c` | Initialize it to `false` |
| `src/message.c` | Add `fast_window_switch` config command and getter |
| `src/yabai.c` | Bump patch version |
| `scripts/install.sh` | Bump `VERSION` |
| `CHANGELOG.md` | Add the config/signal entry |
| `README.md`, `doc/yabai.asciidoc`, `doc/yabai.1` | Document the config and signal |
| `memory-bank/activeContext.md`, `progress.md` | Record the architecture change |
| `~/.config/yabai/yabairc` | Two declarative lines; remove shell call |
| `~/.config/yabai/app_fast_land_signal.sh` | Gate on the config; keep signal-only |
| `~/.config/yabai/app_fast_land.sh`, `app_fast_land.conf` | Delete; no parallel config |

## Implementation Steps

1. Restore `fast_window_switch` as a stored, printable config with default `off`.
2. Remove the callable manager/config files; keep one signal action script.
3. Add `window --fast-focus <pid>` to `src/message.c`; it checks the config,
   compares HID input timestamps, selects the target standard window, switches
   space and focuses the window.
4. Replace the yabairc shell call with `yabai -m config ...` and
   `yabai -m signal --add ...`; reduce the action to one `--fast-focus` call.
5. Build, run unit tests, and inspect the diff for stale manager references.
6. Update version, docs, and memory.

## Dependencies

- None. The runtime dialog with Dock/WindowServer remains unchanged; this change
  only moves control into yabai's config and signal surfaces.

## Success Criteria

- `yabairc` contains no script invocation and no shell control flow.
- `yabai -m config fast_window_switch` returns `on`/`off`.
- `fast_window_switch on` writes `workspaces-auto-swoosh=false` and restarts Dock
  only when the value changes; `off` restores `true`.
- `yabai -m signal --list` shows the `app-fast-land` action.
- With the config `off`, the signal action does nothing; with `on`, it focuses
  the target window via `window --fast-focus`.
- The C command is a single call from the signal action; it uses no jq, ioreg
  or shell window query.
- `make` emits 0 warnings; unit tests pass.
- No `app_fast_land.sh` or `app_fast_land.conf` remains in the user config.
