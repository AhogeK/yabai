# Plan: eliminate Dock space-transition animation at the source

Date: 2026-10-29 · Status: closed (fast landing accepted; WindowServer slide remains; 7.2.19 runtime verified; 7.2.20 source fixes pending runtime) · Scope: macOS 27.2, Dock 2571.1.32.402

## Outcome (2026-10-29)

The earlier `closed (no safe fix in yabai)` conclusion was too strong and is
retracted. Dock-side tests did not demonstrate that the exact telemetry flag
controls the animation:

- `FUN_1000c27c8`'s `SLSTransactionSetManagedDisplayIsAnimating` argument at
  `0x1000c4878` was changed from `1` to `0` at runtime (readback confirmed).
- A 30 fps Dock-click A/B recording of `magpie` (space 2) -> `cmux` (space 1)
  still showed the slide with the flag at `0`.
- Function-hit was not breakpoint-proven: LLDB stopped Dock and the AX click
  could not enter, so this A/B does not prove the patched function was on the
  clicked path.
- `WASpaceFrameAnimation` is not registered in Dock
  (`NSClassFromString` returns nil); Dock imports
  `WindowManager.TransitionAnimation`, and `WindowManager`/`SkyLight` are
  loaded in Dock, but the animation class is not owned by Dock.

The remaining candidates are the WindowServer/WindowManager transition path.
## Safety incident (2026-10-29)

A direct `sudo lldb -p WindowServer` attach stopped WindowServer with
`SIGSTOP`, froze the GUI, and the system auto-restarted. The command was
read-only and made no persistent change; the temporary survey log was cleared
by the reboot. Do not repeat a bare WindowServer attach. Any future runtime
evidence must use non-stopping sampling, or an attach with an explicit
watchdog that detaches on timeout.
Baseline restored to 7.2.18 / OSAX 2.1.41 after the incident; source diff is
clean and no debugger remains.


No safe yabai/SA control point is proven yet. A bare privileged WindowServer
attach is banned; a non-stopping sampler, a watchdog attach with explicit
detach, or a deeper static extraction is required. The baseline at that
incident was 7.2.18 / OSAX 2.1.41; the current source is 7.2.20.
## Native fast landing implementation (2026-10-29, 7.2.20 review fixes)

- `src/event_loop.c`: `APPLICATION_FRONT_SWITCHED` resolves pending
  application windows before selecting a target, prefers the application
  focused window, excludes minimized fallback windows, treats sticky windows
  as visible, waits up to 500 ms for the destination space, and restores the
  Cmd+Tab fence. The AX pending-focus flag no longer suppresses a landing.
- The previous PSN-space lookup and its dead helper were removed.
- `src/space_manager.c`: `skip_window_focus_animation` defaults to false;
  `fast_window_switch` defaults to true and is exposed as a separate config.
- Build: `yabai-v7.2.20`, 0 warnings; tests: 4/4 (visibility and sticky
  predicate).
## Decision (2026-10-29)

- Keep the native fast-landing implementation.
- Accept the WindowServer space-slide animation; it is not removed.
- Runtime debug output restored to off; `skip_window_focus_animation` is off
  and `fast_window_switch` is on.
- Source changes are committed on ai-base as `87d35c7` (code), `d96ed38`
  (docs), and `3089347` (version 7.2.20); the AI record is `a710a3c`.
  dev/master are synchronized with the same three non-AI commits and all
  three branches match origin.
- A reinstall reset `com.apple.dock workspaces-auto-swoosh` to `1`; Dock
  then raced fast landing and produced intermittent animation. The setting is
  back to `0`; Dock restarted at 22:10 and the user confirmed hidden-space app
  switching now has no animation.
- No further WindowServer privileged debugging.

## Semantics (2026-10-29)

- Fast landing means a direct space/window focus request, not a visual
  no-animation guarantee.
- The WindowServer slide remains visible; that is the accepted outcome.
- “Target window lands” in earlier tables means the focus/space request is
  issued, not that the desktop stops sliding.


- Installed and verified: fast landing runs (`result=0`, `SPACE_CHANGED`), WindowServer slide remains.
- WindowServer attach remains banned.


## Objective

Remove the slide animation from Dock-initiated space switches **without**
disabling `workspaces-auto-swoosh` and **without** requiring an external
front-switch script.

The current released workaround is:

- `workspaces-auto-swoosh=false` (Dock no longer follows window ordering)
- `skip_window_focus_animation=off` (yabai does not synthesize a second switch)
- a front-switch script performs `space --focus` and `window --focus`

That workaround removes the animation for the window-order path, but:

- a single Dock click does nothing without the script;
- a second click/reopen uses Dock's application-launch path and still animates;
- every machine must install and register the script.

This plan targets the remaining Dock-side transition itself.

## Evidence (already collected)

- Dock 27.2 contains `Spaces -switchToSpaceForApplicationLaunch:psn:orderedFrontWithNoWindows:`.
  Decompilation shows it bridges a dictionary, consults `appToSpaceTable` /
  `tileOnLaunch`, reads `CGSGetActiveSpace`, and calls inner helpers.
- Dock logs the transition as `switching to space N for window(...) ordered on
  non-visible space` and then `Space display finished animating`.
- Dock contains `fluidSwitching`, `_performingJumpToAnimation`,
  `WASpaceFrameAnimation`, `SpaceSwitcher`, `SpaceSwitcherDisplay`,
  `switchToUserSpace:`.
- Dock imports WindowManager transition symbols
  (`WindowManager.TransitionAnimation.animated`, transition coordinator), so the
  animation decision may live in Dock, WindowManager.framework, or WindowServer.
- Disabling `workspaces-auto-swoosh` removes the window-order follow path but the
  application-launch/reopen path remains animated.
- Synthetic Dock swipes need the macOS 27 IOHID payload (field 4205) plus a
  companion gesture; that is implemented in 7.2.15 and is not the missing piece
  for this path.

## Hypotheses to test (in order)

1. **Dock flag**: `Spaces` carries a jump/fluid state (`_performingJumpToAnimation`
   / `fluidSwitching`) that selects the animated transition. Setting the flag
   false around the launch switch may make it instant.
2. **WindowManager transition**: Dock asks WindowManager for a transition with an
   `animated` option. If the call site can pass `.none` (or an equivalent), no
   animation is scheduled.
3. **Lower-level SLS switch**: Dock's launch path ultimately calls an SLS/CGS
   switch. Replacing it with `SLSManagedDisplaySetCurrentSpace` (already proven
   instant in the direct `space --focus` test) may avoid the animation.
4. **WindowServer duration**: if the duration is decided after Dock returns, only
   a WindowServer-side patch or a transition API can change it.

## Work breakdown

### Phase 1 — Static call-path map (read-only)

- Open the Dock arm64e slice and map every caller of
  `switchToSpaceForApplicationLaunch:psn:orderedFrontWithNoWindows:` and the
  window-order follow path.
- Decompile the inner helpers reached from `sub_1001256d4` and
  `sub_100126b58`; record the argument that selects animation, the owning class,
  and whether the decision is in Dock or WindowManager.
- Identify the ivars/offsets behind `_performingJumpToAnimation` and
  `fluidSwitching`; list their setters and callers.
- Check whether a non-animated `Spaces` method already exists
  (`switchToUserSpace:`, `switchSpace`, transaction variants).
- Output: a call graph with exact addresses, ABI, and a list of candidate
  interception points. Use REA/Ghidra, close the analysis session when done.

### Phase 1 findings (2026-10-29, static)

Target: Dock `2571.1.32.402`, arm64e thin slice
`05afb17136251d5377b14a24c4edf861c67f4c3eab646315b073a972a3e55e8a`
(Ghidra 12.1.4; evidence `ev_b5100245…`, `ev_210eadcc…`, `ev_fec8cb77…`,
`ev_a4796013…`, `ev_99d2b824…`, `ev_d844f59a…`, `ev_a7ee9a35…`).

**Launch path (confirmed):**

| Step | Address | Observation |
|---|---|---|
| Objective-C entry | `0x1001287dc` / stub `0x10024aba0` | `Spaces::switchToSpaceForApplicationLaunch:psn:orderedFrontWithNoWindows:` bridges the dictionary and calls `FUN_1001256d4` |
| Core helper | `0x1001256d4` | Reads `Spaces::_appToSpaceTable` (`0x1003241d0`) and `_tileOnLaunch` (`0x1003241c8`); final branch calls `FUN_100126b58` after `CGSGetActiveSpace` |
| Space lookup | `0x100126b58` | Finds the `ManagedSpace` whose `_spid` equals the active space; invokes closure `0x100125d34` |
| Launch closure | `0x100125d34` | Calls `FUN_100188858(space, x1=1, x2=0, x3=0, x4=1)` |
| Transition executor | `0x100188858` | Large Swift transition routine; `CGSMoveManagedSpaceToDisplayIndex` at `0x1001895c8` is behind a `param_2 & 1` branch; `CGSSpaceSetFrontPSN` at `0x100189080` is skipped when `param_5 == 1` (launch passes 1) |

The launch closure's flag tuple (`1,0,0,1`) differs from
`Spaces::switchToUserSpace:` → `FUN_100124584`, which calls the same executor
with `(0,1,0,1)`. This is the strongest static candidate for the
application-launch animation/ordering difference; it is not yet proof that
`param_2` means "animated".

**Window-order path (separate):**

`Spaces::handleWorkspacesTileOrderChangedInSpace:` (`0x100131668`) →
`FUN_10013159c` (`0x10013159c`) → `FUN_100126b58` with closure
`0x1001315cc`. That closure only coalesces the event through
`FUN_10013679c` and a dispatch source `data_or`; it does not call
`FUN_100188858`. This path is not the launch closure.

**Animation flags / WindowManager:**

- `SpaceSwitcher` diagnostics (`fluidSwitching`, `_performingJumpToAnimation`)
  live at `0x100271060` / `0x1002710e0`; xrefs are `FUN_10018ab1c`
  (state logger) and `FUN_100193904` (clear-on-gesture-end). Their callers are
  gesture/UI paths, not the launch closure, so hypothesis 1 is not supported
  for the launch path.
- WindowManager `WindowTransitionAnimation` metadata is imported
  (`0x1002320ac`); its xrefs (`0x1001a98e0`, `0x1001ac418`, `0x1001ad308`)
  are separate window-transition routines. No static edge from the launch
  chain was found, so hypothesis 2 is not supported for this path.
- `FUN_10018a674` (`0x10018a674`) is the direct current-space setter: it writes
  `self+0x58` and calls `_CGSManagedDisplaySetCurrentSpace` at `0x10018a71c`.
  `FUN_10012d5ac` finds a space by `_spid` and calls this setter; it is not on
  the launch chain. This is the proven instant primitive to compare against.

**Candidate interception points (smallest first):**

1. Launch closure `0x100125d34`: change/log `x1` (currently `1`) before
   `FUN_100188858`; this directly tests the `param_2` branch without touching
   the method dictionary parsing.
2. `FUN_100188858` entry or its `CGSMoveManagedSpaceToDisplayIndex` branch:
   gate/replace only the launch call; requires display/space mapping.
3. `FUN_10018a674` / `_CGSManagedDisplaySetCurrentSpace`: use the proven
   instant setter instead of the launch transition, but preserve front-app and
   tile ordering behavior.
4. Swizzle the Objective-C launch method (`0x1001287dc`): most invasive; needs
   the app-to-space dictionary lookup.

**Next minimal experiment:** a debug-only SA hook at the launch closure (or
`FUN_100188858` entry) that logs the flag tuple and, in a second run, forces
`x1=0` only for the launch closure. Success = Dock click/reopen lands without
the slide, no Dock crash, and tile ordering still correct. If unchanged, hook
`CGSMoveManagedSpaceToDisplayIndex` and compare; if still unchanged, test the
direct setter path.

**Runtime caveat (2026-10-29):** the current machine has
`workspaces-auto-swoosh=0` and the `application_front_switched` script active.
That is the workaround, not the original reproduction environment; it masks the
animation and makes current LLDB/sample negatives non-evidence about the
original launch path. Restore the baseline (auto-swoosh enabled, script
disabled, Dock restarted) before drawing runtime conclusions.

**Tooling constraint (2026-10-29):** attaching LLDB to the live Dock froze
the desktop and required an out-of-band kill. Do not use LLDB on the live Dock
for this investigation; use static analysis and non-pausing evidence first,
and only an explicitly user-approved debug SA build/restart for runtime tests.

### Phase 1 root cause (2026-10-29)

- Runtime baseline sample: `_window_spaces_notification_handler` → Dock
  `0x100111b60` → `0x1001231f8` → `0x100123614` → `FUN_100126768`
  (`0x1001268f0`) → `FUN_100188858` → `FUN_1000c27c8` → SkyLight.
- In `FUN_1000c27c8`, the animation flag is set at `0x1000c4878`:
  `mov w2,#1` immediately before
  `SLSTransactionSetManagedDisplayIsAnimating` (`0x1000c487c`).
- Other Dock paths set the same API with `w2=0`
  (`FUN_1000c63ac` at `0x1000c6708`, `FUN_1000c6878` at `0x1000c6bd8`),
  confirming the `1` is the animated variant.
- SA profile `2571.1.32.402` now patches that one instruction to
  `mov w2,#0` after checking `__TEXT` membership and the exact opcode;
  mismatch or `vm_protect` failure leaves Dock untouched (fail-closed).
- This targets the app/space transition path, not `_performingJumpToAnimation`
  or the launch method.

Unknowns: whether `param_2` selects animation or space reordering; whether
`CGSMoveManagedSpaceToDisplayIndex` is the actual WindowServer animation
trigger; display UUID mapping for the direct setter; multi-display behavior;
whether WindowServer commits the transition after Dock returns.

### Phase 2 — Minimal runtime experiment (SA payload)

- Add a debug-only SA opcode (or environment-gated path) that toggles one
  candidate at a time:
  - set `_performingJumpToAnimation` false before the launch switch;
  - set `fluidSwitching` false;
  - swizzle only the launch method to log arguments and call the original.
- Run on a test build with the Dock build whitelist; log every step.
- Success: one candidate removes the animation for a Dock click/reopen, with no
  Dock crash and no loss of window ordering.
- Failure: record the exact call sequence and move to the next hypothesis.

### Phase 3 — Production implementation

- Implement the smallest winning interception in `src/osax/payload.m`
  (method swizzle or flag set), gated by:
  - Dock build whitelist (`2571.1.32.402` first);
  - arm64 only, where required;
  - fail-closed: if the class/method/ivar is missing, leave Dock untouched and log.
- Do not remove the existing workaround until the new path is validated on a
  clean configuration (`workspaces-auto-swoosh` default, no script).
- Keep `skip_window_focus_animation` off by default; the deep fix must not need
  the synthetic gesture.

### Phase 4 — Verification matrix

| Case | Expected |
|---|---|
| Dock single click, running app on hidden Space | instant landing, correct window |
| Dock double click / reopen | instant landing, correct window |
| Cmd-Tab to app on hidden Space | instant landing |
| `yabai -m space --focus` | unchanged, instant |
| `yabai -m window --focus` cross-Space | unchanged, instant |
| Rapid same-app switching | no black screen, no ping-pong |
| Mission Control / full-screen Space | no regression |
| Multi-display, Dock on another display | no wrong-display switch |
| Unknown Dock build | SA disables the patch, no crash |

### Phase 5 — Documentation and rollback

- Add a config switch if the behavior needs an opt-out.
- Update `CHANGELOG`, README caveat, `memory-bank/domains/space-management/`
  scenarios and references.
- Keep the current workaround documented as the fallback.
- Record the exact Dock build and offsets; update the whitelist procedure when
  Dock changes.

## Safety boundaries

- Never patch an unverified Dock build; fail closed (R21).
- Do not restart Dock or yabai automatically; the user runs the restart (R3).
- Validate every fixed-address/ivar access against its section (R21).
- Keep the change local to the launch/window-order path; do not alter Mission
  Control or full-screen transitions without separate evidence.
- If the animation is committed in WindowServer after Dock returns, stop and
  reassess; do not ship a Dock-only patch that cannot work.

## Open questions

- Is the launch-path animation selected in Dock, WindowManager, or WindowServer?
- Does the launch method expose a non-animated variant or an animation option?
- Does disabling the animation affect window ordering or Dock-icon-follow?
- Can the same interception cover the window-order follow path, removing the
  need for `workspaces-auto-swoosh=false`?
- What is the rollback if a future Dock build changes the method signature?

## Exit criteria

- Default Dock settings, no front-switch script: Dock click, double-click/reopen,
  Cmd-Tab and yabai focus commands all land without the desktop slide.
- Rapid switching is stable; no black screen, no wrong app, no Dock crash.
- Unknown Dock builds remain fail-closed.
- The old workaround still works and is documented as fallback.
