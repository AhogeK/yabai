# Project Brief - yabai

## Purpose

yabai is a tiling window manager for macOS, built as a fork of chunkwm.
It manipulates window layout via private SkyLight APIs and a scripting-addition
injected into Dock.app for full window control (requires SIP disabled or partial).

## Architecture Scope

- **Core**: Window tree (BSP / Stack / Float), space management, display management
- **IPC**: Unix domain socket server accepting scripting commands
- **Event System**: Carbon event tap + SkyLight observer notifications
- **Scripting Addition**: Injected into Dock.app for elevated window access

## Hard Constraints

- macOS-only; no cross-platform abstraction layers
- C11 standard; no C++ or Objective-C in core logic
- Must support both SIP-enabled (limited) and SIP-disabled (full) modes
- IPC protocol must remain backward-compatible with existing yabairc configs
- macOS 11.0+ (Big Sur) minimum deployment target
- Universal binary: x86_64 + arm64