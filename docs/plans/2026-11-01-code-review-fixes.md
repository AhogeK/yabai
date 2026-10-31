# Plan: Code-review fixes for fast window switch

Date: 2026-11-01 · Status: in-progress; 7.2.41 build and 6/6 unit tests pass, runtime deploy pending

## Objective

Resolve every finding from the two-axis review and make the uncommitted tree coherent. The canonical implementation is the C `window --fast-focus <pid>` path. The signal action will call that single command; shell/jq/ioreg target selection will not be duplicated.

## Affected Files

| File | Change |
|---|---|
| `src/message.c` | Fix fast-focus input gate and target-window selection; remove duplicated shell-era assumptions |
| `src/space_manager.c` | Keep opt-in default off; no unrelated changes |
| `makefile` | Restore a deterministic `workspaces-auto-swoosh=true` deploy default; English log line |
| `tests/src/tests.m` | Register new tests |
| `tests/src/fast_focus.c` | Add pure tests for input-gate and target-selection predicates |
| `README.md`, `doc/yabai.asciidoc`, `doc/yabai.1` | Document the exact signal action and C command; remove placeholder/contradictory wording |
| `examples/yabairc` | Add the opt-in config and signal action |
| `CHANGELOG.md` | Remove unverified "stops loop" claim; describe tested behavior only |
| `memory-bank/activeContext.md`, `progress.md` | Compress/archive to R12 limits |
| `src/window_manager.h` | Remove stray blank line |
| `.gitignore` | Ignore `.omp/` agent artifacts |
| `docs/plans/*` | Mark the rejected/superseded plan; keep one active spec |

## Implementation Steps

1. Refactor fast-focus input gate into a pure helper with `CGEventSourceSecondsSinceLastEventType(kCGAnyInputEventType)`.
2. Refactor target selection into a focused-first helper; use it for visible and hidden windows.
3. Add unit tests for gate acceptance and target precedence.
4. Make `make deploy` set `workspaces-auto-swoosh=true`; keep `fast_window_switch on` as the explicit opt-in override.
5. Update docs/example to the exact `--fast-focus` action; remove placeholders.
6. Correct CHANGELOG claims; archive/compress memory files; ignore `.omp`.
7. Build, run unit tests, run an integration smoke test against a hidden multi-window app, and report.
8. Do not commit/restart yabai; user must deploy/restart.

## Success Criteria

- One fast-focus implementation, no duplicate shell selection path.
- Visible and hidden multi-window apps choose the AX-focused window first.
- Gesture/scroll activity counts as new input; no self-trigger loop.
- `make` 0 warnings; all unit tests pass; new tests fail on the old gate/selection logic.
- README/man/example describe the same command the source implements.
- Memory files within R12 limits; `.omp` ignored.
- No unverified CHANGELOG claim.

## Dependencies

- C private APIs already used by yabai; no new framework.
- User must run `make deploy` and restart the service after review.
