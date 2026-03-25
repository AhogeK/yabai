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
- Backward compatibility required

## Memory Management

- Arena allocators for window tree nodes
- Explicit ownership via comments
- No RAII - manual `alloc`/`free` tracking required

## Scripting Addition Injection

1. Build `payload.m` → binary blob
2. Build `loader.m` → binary blob
3. Embed via `xxd -i` → `*_bin.c` files
4. Runtime: inject into Dock.app via Mach ports