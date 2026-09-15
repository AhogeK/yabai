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

## 目标系统与能力代际速查（细节见领域层）

| 项目 | 当前值 |
|---|---|
| 目标系统 | macOS 27.0 (26A428)；Dock 2571.0.6.402；WindowManager.framework 462.0.8 |
| 空间创建 | **G3**：`WindowManager.framework`（27 起 Dock 无本地实现） |
| 空间销毁/移动 | 仍走 Dock 内 `removeSpace` / `moveSpace`（pattern 命中） |
| Spaces / DPPM 单例 | 由 pattern 在运行时解码（27.0：`0x100409bb0` / `0x100409c50`） |

- 偏移/pattern/符号全表与历史版本矩阵 → `domains/dock-reverse-engineering/references.md`
- 版本适配排查流程 → `domains/dock-reverse-engineering/scenarios.md`
- 空间三代实现与不变量 → `domains/space-management/principles.md`
- SA 协议/属性位/版本门 → `domains/scripting-addition/{principles,references}.md`

### Swift 调用约定速查（26/27 通用）

| 寄存器 | 角色 |
|--------|------|
| `x0/x1` | 参数 1/2（String 等 2-word 值） |
| `x20` | self（实例方法）/ metatype（静态方法） |
| `x21` | swift_error*（throwing 方法返回；调用前清零） |
| `x0` | 返回值 |

### Sandbox Constraints

- IOKit (`CGDisplayIOServicePort`) 在 Dock 沙箱返回 `MACH_PORT_NULL`（静默失败）
- 用 `CGDisplayCreateUUIDFromDisplayID`（CoreGraphics，沙箱安全）
