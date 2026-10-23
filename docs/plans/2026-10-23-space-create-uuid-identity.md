# Plan: Space create identity fix (macOS 27)    Date: 2026-10-23 · Status: completed

## Objective

Stop `yabai -m space --create` from stamping the display UUID as the new space's identity.
Every space created by yabai on one display currently shares that display's UUID, and
macOS 27's WindowManager restore maps all same-identity entries onto a single space at
login (`managed space order: [6, 6, 6, 6, 6, 6, 6]`), which leaves Mission Control with one
desktop and no wallpaper. The system's own "+" button gives each space a fresh UUID; mirror
that behaviour and keep the display UUID only for placement verification.

Evidence (2026-10-23):
- before shutdown: `[50, 3258, 58, 81, 90, 84, 72, 2380]` (8 distinct ids)
- after boot 15:11:40: `[6, 6, 6, 6, 6, 6, 6]`; yabai started 15:11:44 (4s later)
- yabai-created space 26: `uuid = 37D8832A-...` (display UUID)
- system-created space 33 via Mission Control "+": `uuid = 442D311F-...` (unique)

## Affected Files

- `src/osax/payload.m`: generate a random UUID for the macOS 27 create helper; log and
  verify the resulting space's display
- `src/osax/common.h`: `OSAX_VERSION` 2.1.33 → 2.1.34 (payload changed)
- `src/yabai.c`: `PATCH` 5 → 6
- `scripts/install.sh`: `VERSION` 7.2.5 → 7.2.6
- `CHANGELOG.md`: 7.2.6 entry
- `doc/yabai.1`: manual date → 2026-10-23

## Implementation Steps

1. payload.m: build `CFUUIDCreate` + `CFUUIDCreateString`, bridge that string into the
   helper instead of `display_uuid`; abort cleanly if UUID generation fails. (low)
2. payload.m: after a non-zero space id, compare `SLSCopyManagedDisplayForSpace(new_id)`
   with the requested display and log a warning on mismatch. (low)
3. Version bump in the four code/version locations plus CHANGELOG and manual date. (low)
4. Build with `make BUILD_PATH=/tmp/...` and confirm zero warnings. (low)

## Dependencies

- Requires a Dock payload reload (`yabai --load-sa`) and then a system space-config reset
  (`defaults delete com.apple.spaces`, `killall cfprefsd`, reboot) to clear the existing
  duplicate identities. Deployment is performed by the user; no service restarts by the agent.

## Success Criteria

- `make` completes with no warnings.
- After reload, `yabai -m space --create` produces a space whose `uuid` differs from the
  display UUID (checked via `SLSCopyManagedDisplayForSpace` / SLS dump).
- After the config reset and reboot, `managed space order` shows distinct ids and Mission
  Control keeps a working desktop background.

## Completion Notes (2026-10-23)

- Code shipped as 7.2.6 / OSAX 2.1.34; build clean (0 warnings).
- Runtime proof: `space --create` returned id 40 with `uuid=ACE42D27-...` (unique, not the display UUID).
- Recovery of the pre-existing damage: `defaults delete com.apple.spaces` + `killall cfprefsd` + logout/reboot. The 42-byte stub file after deletion is normal (`{}`).
- Post-reboot state: `managed space order` = `[1]` / `[6]` / `[7]`, `query --spaces` count=unique=3, wallpaper restored.
- Lesson: the helper's 4th argument is the new space's identity, not a display binding; "creation succeeded" alone never proved the semantics.
