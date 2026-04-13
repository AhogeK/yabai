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

### Call Chain (Confirmed via LLDB)

```
"+" 按钮 → 0x1f07d8 (Swift method, x0=display_id int32, x20=Spaces self)
          → 内部: ManagedSpace alloc + 数组追加 + CGS 注册
          → DPPM addSpace:forDisplayUUID: (壁纸)
```

### Swift Calling Convention (macOS 26)

| Register | Role |
|----------|------|
| `x0` | First argument (display_id as int32_t → w0) |
| `x20` | Swift `self` (Spaces singleton) — callee-saved |

### Key Classes (DockCore Swift Framework)

- `Spaces`: 空间数据模型 (`<Spaces: 0x...>`)
- `SpacesBarWindowController`: 单显示器视图控制器 (含 DisplayInfo, currentSpace)
- `DockCore.ExposeSpacesBarController`: Mission Control 空间栏总指挥
- `DockCore.SpacesBarAddLayerController`: "+" 按钮 UI 控制器
- `DockCore.WallpaperAgentDesktopPictureManager`: 壁纸管理器 (15 实例方法, 0 类方法)

### Dynamic Singleton Discovery

- **Spaces**: DOUBLE-ANCHOR (bl→space_create_entry_fp + backtrack adrp/add), offset `0x488028`
- **DPPM**: Control-flow fingerprint (cbnz+str guard in setter), offset `0x4880d0`

### Manual UI Path (28 layers)

```
RunLoop Source1 (HIServices) → mshPerform → ... → #05 (0x22abb8) array append
#05: Swift.Array._appendElementAssumeUniqueAndCapacity ← key array update point
```
