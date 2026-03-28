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
| `0x1f07d8` | 顶层创建入口 | 已实现 |
| `0x1eb33c` | 数组遍历 | 已确认 |
| `0x285564` | CGSMoveManagedSpaceToDisplayIndex | 已确认 |
| `0x19e150` | DPPM addSpace:forDisplayUUID: | 已确认 |

### Call Chain

```
0x1f07d8 → 0x143e1c → 0x1eb33c → 0x285564 → addSpace:forDisplayUUID:
```

## 已实现的 Hook

| Hook | 偏移 | 文件 |
|------|------|------|
| `addSpace:forDisplayUUID:` | ObjC Method | payload.m:858-864 |
| `SPACE-ENTRY-HOOK` | `0x1f07d8` | payload.m:900-1014 |