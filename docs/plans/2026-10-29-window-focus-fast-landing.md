# Plan: window focus fast landing on hidden desktops

Date: 2026-10-29 · Status: completed (included in 7.2.18) · Versions: 7.2.13 → 7.2.18

## Objective

Restore the immediate landing that `window --focus` used to have when the target
window lives on a desktop that is not visible. The user's scripts must stay
unchanged: `same_app_window_forward.sh` keeps calling only `window --focus`.

## Evidence

- `src/message.c` `COMMAND_WINDOW_FOCUS` previously called only
  `window_manager_focus_window_with_raise()` (`_SLPSSetFrontProcessWithOptions`,
  `make_key_window`, `AXRaise`). The daemon never switched the space itself.
- Daemon log on 7.2.13: `window --focus 2237` → `WINDOW_FOCUSED 2237` →
  `SPACE_CHANGED 166`, with no `space --focus` command in between. The switch is
  macOS's implicit reaction to the window activation.
- On macOS 27.2 that implicit switch is animated; `space --focus` (SA/SLS) lands
  immediately. This is a system behavior change, not a script regression.
- User feedback (2026-10-29): window focus itself is the trigger and must not be
  explained away as a script-level problem.
- 30 fps screen recordings on 7.2.13 did not capture a slide in same-app
  same-display or cross-display tests, but the user was interacting with the
  machine during the runs (`MOUSE_*` / `APPLICATION_FRONT_SWITCHED`), so those
  samples are not conclusive.

## Change

`src/message.c`, `window --focus` branch:

```c
if (sid && !space_is_visible(sid) && !window_check_flag(acting_window, WINDOW_MINIMIZE)) {
    space_manager_focus_space(sid);   // SA/SLS, same path as `space --focus`
}
window_manager_focus_window_with_raise(...);
```

- Runs inside the focus command; the caller still sends only `window --focus`.
- Minimized windows keep the previous behavior.
- If the space switch is refused (Mission Control, display animating, SA
  unavailable), the original native switch remains the fallback.

## Verification

| Check | Result |
|---|---|
| Build (`-Wall -Wextra`) | 0 warnings / 0 errors |
| `make -C tests` | 2 succeeded / 0 failed |
| Runtime on 7.2.14 | pending: user must `make install` and restart yabai |
| 7.2.13 capture | inconclusive: user input stole focus during recording |

## Open items

- Install 7.2.14 and confirm `opt+shift+tab` across hidden desktops lands without
  the horizontal desktop animation.
- If it still animates, compare with the upstream `skip_window_focus_animation`
  gesture path (cross-display warps the cursor) before changing the design.
- Environment observation: `com.apple.dock mru-spaces = 1` on this machine;
  README already recommends disabling it. It reorders spaces after a focus and
  makes index-based cycling harder to reason about.
