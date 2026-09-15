# Technical Context - yabai

## Build Toolchain

| Component       | Configuration                                    |
|-----------------|--------------------------------------------------|
| C Standard      | C11 (`-std=c11`)                                 |
| Compiler        | Apple Clang (xcrun clang)                        |
| Deployment      | macOS 11.0+ (`-mmacosx-version-min=11.0`)        |
| Architectures   | Universal: x86_64 + arm64 (osax payload: arm64e) |
| Debug Build     | `-g -O0 -fvisibility=hidden`                     |
| Release Build   | `-O3 -DNDEBUG -fvisibility=hidden`               |

> 本机 `xcrun clang` 若报 Xcode license 未接受，可临时 `DEVELOPER_DIR=/Library/Developer/CommandLineTools make`。

## Private Frameworks

| Framework    | Purpose                              | Risk Level |
|--------------|--------------------------------------|------------|
| SkyLight     | Core window management, spaces       | HIGH       |
| **WindowManager** | **macOS 27 起空间/窗口管理实现（Dock 22+ 链接，仅存于 dyld shared cache）** | HIGH |
| Carbon       | Event taps, accessibility            | MEDIUM     |
| Cocoa        | Obj-C bridging, app lifecycle        | LOW        |

## SIP & Code Signing

- **SIP Disabled**: scripting-addition injection into Dock.app（`/Library/ScriptingAdditions/yabai.osax`）
- **SIP Enabled**: reduced window control capabilities
- **Code Signing**: requires `yabai-cert` identity or ad-hoc

## macOS 27 API Changes（Dock 2571.0.6.402 / WindowManager 462.0.8）

### 移除/失效

| 符号 | 状态 |
|--------|------|
| Dock Swift `space_create_entry` (26.6: `0x1f07d4`) | 27 已移除 |
| `CGSAddManagedSpace` / `CGSManagedDisplayAddSpace` / `SLSSpaceCreate` | 0x0（26 起失效） |
| DPPM setter 控制流指纹（`find_dppm_singleton_instructions`） | 27 无匹配（改用 pattern 路径） |

### macOS 27 关键偏移（Dock arm64e）

| 偏移 | 功能 | 状态 |
|------|------|------|
| `0x192bc` | setFrontWindow 入口（cbz w1 早退 + pacibsp 序言） | ✅ 唯一命中 |
| `0x18b9a0` | removeSpace | ✅ pattern 命中 |
| `0x18c554` | moveSpace | ✅ pattern 命中 |
| `0x227508` | animation-time 指令序列 | ✅ pattern 命中 |
| `0x100409bb0` | Spaces 单例全局（`__common`） | ✅ pattern 解码 |
| `0x100409c50` | DPPM 单例全局（`__common`） | ✅ pattern 解码 |

### macOS 27 空间创建（WindowManager.framework）

```c
// dlsym（mangled Swift 符号，无 Dock 偏移依赖）
"$s13WindowManagerAACMa"                                    // type metadata accessor
"$s13WindowManagerAAC6sharedABvgZ"                          // static shared getter
"$s13WindowManagerAAC38synchronouslyRequestCreateManagedSpace11displayUUIDs6UInt64VSSSg_tKF"
"$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ"  // String(NSString)
"swift_errorRelease"

// Swift ABI: 静态 getter 需 x20 = metatype；实例方法 x20 = self，
// String 占 x0/x1，返回值 x0，throws 错误在 x21（调用前必须清零）
```

### Swift 调用约定速查（macOS 26/27）

| 寄存器 | 角色 |
|--------|------|
| `x0/x1` | 参数 1/2（String 等 2-word 值） |
| `x20` | self（实例方法）/ metatype（静态方法） |
| `x21` | swift_error*（throwing 方法返回） |
| `x0` | 返回值 |

### Sandbox Constraints

- IOKit (`CGDisplayIOServicePort`) 在 Dock 沙箱返回 `MACH_PORT_NULL`
- 用 `CGDisplayCreateUUIDFromDisplayID`（CoreGraphics，沙箱安全）
