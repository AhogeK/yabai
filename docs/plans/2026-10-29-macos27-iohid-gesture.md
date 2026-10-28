# Plan: macOS 27 IOHID gesture payload

Date: 2026-10-29 · Status: completed (user-validated) · Version: 7.2.18

## Objective

Restore immediate focus landing for Dock icon clicks, Cmd-Tab, the macOS
"switch to a Space with open windows" setting, and `window --focus` on macOS 27.

## Evidence

- The daemon's `skip_window_focus_animation` path was enabled at runtime and the
  Dock click still animated. The system preference
  `workspaces-swoosh-animation-off` was also tested and did nothing.
- noswoosh and iss (open source) document the macOS 27 change: the Dock validates
  synthetic Dock swipes against a serialized raw IOHID queue payload in CGEvent
  field 4205, and each DockControl event must be paired with a companion gesture
  event. Without that, the Dock silently ignores the gesture.
- `space_manager_focus_space_using_gesture` posted only the pre-27 event shape, so
  the bypass could not work on 27.

## Change

`src/space_manager.c`:

- `space_manager_augment_dock_event`: serialize the event, append the IOHID
  payload (queue header + fluid-touch record + velocity record) under field 4205,
  and rebuild the event with `CGEventCreateFromData`.
- `space_manager_post_macos27_swipe`: post began / changed / ended DockControl
  events, each paired with a type-29 companion gesture; direction follows the
  natural-scrolling setting; near-zero progress plus a ±9999 fling commits the
  switch without travel.
- `space_manager_focus_space_using_gesture`: on macOS 27+ use the new path; the
  pre-27 path is unchanged.
- `workspace_is_macos_27_or_later` gates the two paths.
- `skip_window_focus_animation` stays off by default. Enabling it while Dock
  window-order follow is disabled makes the gesture and yabai's space focus
  fight, so two applications can bounce back and forth.
- Final configuration: `workspaces-auto-swoosh=false` plus
  `skip_window_focus_animation=off`; the Dock no longer performs the switch.
- On macOS 27+, space focus waits for an animating display to settle before
  switching, and window focus aborts if the destination space never becomes
  visible.

## Verification

| Check | Result |
|---|---|
| Runtime | validated by user: no animation or feedback loop reported |
| `make -C tests` | 2 succeeded / 0 failed |

## Risks / unknowns

- The payload layout is undocumented; a future macOS release can invalidate it.
- The gesture is posted after `APPLICATION_FRONT_SWITCHED` / `WINDOW_FOCUSED`.
  If the Dock has already committed the animated transition, the gesture may be
  too late. This must be checked visually; if it fails, the animation is decided
  inside the Dock's `Spaces` path and needs a different lever.
- Cross-display focus still warps the cursor to the target display center.
- On macOS 27+ the bypass is enabled by default; `skip_window_focus_animation off`
  restores the native animation.
