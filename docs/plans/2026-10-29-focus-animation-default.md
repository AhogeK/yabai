# Plan: focus-animation bypass for every focus source

Date: 2026-10-29 · Status: rejected (runtime test failed; code reverted) · Attempted: 7.2.15
> Superseded by `docs/plans/2026-10-29-macos27-iohid-gesture.md` (macOS 27 IOHID payload).

## Objective

Restore the immediate landing for every focus-induced space switch on macOS 27.2,
not only `yabai -m window --focus`:

- Dock icon click (app activation)
- Cmd-Tab application switch
- macOS "When switching to an application, switch to a Space with open windows"
- `yabai -m window --focus`

The user's scripts stay unchanged; the `application_front_switched` signal remains
commented out.

## Evidence

- User observation: after the 27.2 update, Dock clicks and Cmd-Tab switch to the
  app's hidden desktop with the macOS horizontal animation; before, the same
  actions landed immediately as window-focus jumps.
- `src/space_manager.c`: the setting defaulted to `false`; the user's yabairc does
  not set it. With the setting off, the daemon never intervenes, so macOS 27.2
  runs its native animated switch.
- `src/event_loop.c`: `APPLICATION_FRONT_SWITCHED` and `WINDOW_FOCUSED` only call
  `SLSSpaceSetFrontPSN` + `space_manager_focus_space_using_gesture()` when
  `g_space_manager.skip_window_focus_animation` is true.
- 7.2.14 only covers the `window --focus` command; it cannot see Dock clicks or
  Cmd-Tab before macOS starts the transition.

## Change

- Attempted: `src/workspace.m/.h` `workspace_is_macos_27_2_or_later()`;
  `skip_window_focus_animation = true` by default on 27.2+; example and manual
  updated. All changes reverted after the live test failed.

## Verification

| Check | Result |
|---|---|
| Build (`-Wall -Wextra`) | 0 warnings / 0 errors |
| `make -C tests` | 2 succeeded / 0 failed |
| Runtime 7.2.15 | not installed (changes reverted) |
| Live setting on 7.2.13 | **failed**: `skip_window_focus_animation on` did not remove the Dock-click animation |

## Risks

- The bypass synthesizes a high-velocity Dock swipe. On a cross-display jump it
  warps the cursor to the target display center; same-display switches do not.
- If the synthetic gesture no longer skips on 27.2, the visible result would be a
  fast horizontal slide. This must be checked visually before closing.
- Users who prefer the native animation can set `skip_window_focus_animation off`.

## Result and next step

The synthetic-gesture bypass does not skip the 27.2 transition for Dock or
Cmd-Tab. The attempted default change was reverted and never committed.

- Next: validate a system-level animation preference
  (`defaults write com.apple.dock workspaces-swoosh-animation-off -bool YES`,
  manual Dock restart).
- If that fails, inspect Dock's `fluidSwitching` / `_performingJumpToAnimation`
  state around `switchToSpaceForApplicationLaunch:psn:orderedFrontWithNoWindows:`.
