# Technical Context - yabai

## Build Toolchain

| Component       | Configuration                                    |
|-----------------|--------------------------------------------------|
| C Standard      | C11 (`-std=c11`)                                 |
| Compiler        | Apple Clang (xcrun clang)                        |
| Deployment      | macOS 11.0+ (`-mmacosx-version-min=11.0`)        |
| Architectures   | Universal: x86_64 + arm64                        |
| Debug Build     | `-g -O0 -fvisibility=hidden`                     |
| Release Build   | `-O3 -DNDEBUG -fvisibility=hidden`               |

## Private Frameworks

| Framework    | Purpose                              | Risk Level |
|--------------|--------------------------------------|------------|
| SkyLight     | Core window management, spaces      | HIGH       |
| Carbon       | Event taps, accessibility            | MEDIUM     |
| Cocoa        | Obj-C bridging, app lifecycle        | LOW        |

## SIP & Code Signing

- **SIP Disabled**: scripting-addition injection into Dock.app
- **SIP Enabled**: reduced window control capabilities
- **Code Signing**: requires `yabai-cert` identity or ad-hoc

## macOS 26 Tahoe API Changes

### Removed Symbols

| Symbol | Status |
|--------|--------|
| `CGSAddManagedSpace` | 0x0 (失效) |
| `CGSManagedDisplayAddSpace` | 0x0 (失效) |
| `SLSSpaceCreate` | 0x0 (失效) |

### Key Function Offsets (macOS 26.4 Tahoe)

| 偏移 | 功能 | 状态 |
|------|------|------|
| `0x1f07d8` | space_create_entry (Swift method) | ✅ 已实现 |
| `0x1eb33c` | 数组遍历 | ✅ 已确认 |
| `0x285564` | CGSMoveManagedSpaceToDisplayIndex | ✅ 已确认 |
| `0x19e150` | DPPM addSpace:forDisplayUUID: | ✅ 已确认 |

### Call Chain

```
0x1f07d8 → internal: ManagedSpace alloc + array append + CGS → addSpace:forDisplayUUID:
```

### Swift Calling Convention

```c
// x0 = display_id (int32_t, use w0)
// x20 = Spaces singleton (Swift self, callee-saved)
#define asm__call_space_create_tahoe(display_id, spaces_self, func) \
    asm volatile( \
        "mov w0, %w[did]\n" \
        "mov x20, %[self]\n" \
        "blr %[fp]\n" \
        : : [did] "r" ((uint32_t)(display_id)), \
            [self] "r" ((uintptr_t)(spaces_self)), \
            [fp] "r" ((uintptr_t)(func)) \
        : "x0","x1","x2","x3","x4","x5","x6","x7", \
          "x8","x9","x10","x11","x12","x13","x14","x15", \
          "x16","x17","x19","x20","x30","memory")
```

### Compiler Optimizations (Xcode 16.3+)

- **Deferred stack allocation**: `sub sp` removed from prologue
- **add+ldr fusion**: `adrp + add + ldr` → `adrp + ldr Xd, [Xn, #imm*8]`
- DPPM offset `0xd0` fits in LDR immediate (12-bit × 8 = max 32760)

### Sandbox Constraints

- IOKit (`CGDisplayIOServicePort`) returns `MACH_PORT_NULL` in Dock sandbox
- Use `CGDisplayCreateUUIDFromDisplayID` (CoreGraphics, sandbox-safe)
