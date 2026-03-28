# System Patterns - yabai

## Core Architecture Patterns

### Event Loop (Event-driven)

```
Carbon Event Tap → Event Handler → Window Manager Update → IPC Response
SkyLight Observer → Callback → State Update → Client Notification
```

### Window Tree (BSP - Binary Space Partition)

```
                    [Root]
                   /      \
              [Left]      [Right]
             /     \      /      \
         [Win1]  [Win2] [Win3]  [Win4]
```

- Insert: split parent, rebalance
- Remove: merge siblings, rebalance
- Types: BSP (tiling), Stack (layered), Float (unmanaged)

### IPC Protocol (Unix Domain Socket)

- Path: `/tmp/yabai_<user>.socket`
- Format: `<command> [args...]`
- Response: JSON or plain text

## Memory Management

- Arena allocators for window tree nodes
- Explicit ownership via comments
- No RAII - manual `alloc`/`free` tracking required

## Scripting Addition Injection

1. Build `payload.m` → binary blob
2. Build `loader.m` → binary blob
3. Embed via `xxd -i` → `*_bin.c` files
4. Runtime: inject into Dock.app via Mach ports

## macOS 26 Space Creation

### Call Chain

```
"+" 按钮 → 0x1f07d8 (顶层入口)
         → 0x143e1c (数组追加 + CGS)
         → 0x285564 (CGSMoveManagedSpaceToDisplayIndex)
         → addSpace:forDisplayUUID: (壁纸)
```

### Key Classes

- `DisplaySpaces._spaces`: Swift Array，需要追加新 space
- `DockCore.WallpaperAgentDesktopPictureManager`: 壁纸窗口