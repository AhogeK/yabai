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
| 目标系统 | macOS 27.2 (26B123)；Dock 2571.1.32.402；WindowManager.framework 462.1.41.404 |
| 空间创建 | 27.2：Dock helper `0x20ce00`；27.0/27.1：`0x2bb62c`；第 4 参数是**新空间身份**，必须传新 UUID；按 Dock 构建白名单 fail-closed |
| 空间销毁/移动 | 27.2：`CGSSpaceDestroy` / `CGSMoveManagedSpaceToDisplayIndex` / `SLSTransaction*`；旧 Dock removeSpace/moveSpace 在 27.2 不存在 |
| Spaces / DPPM 单例 | 27.2：Spaces 槽 `0x329be0`；DPPM 已转 Swift，未使用；27.0：`0x100409bb0` / `0x100409c50` |

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

## REA / Hopper（2026-10-29）

- REA 的 Hopper provider 用 `hopper -Y bootstrap.py ...` 注入 bridge；Hopper 已在运行时该命令返回 0 但**不执行脚本**，REA 会等到启动超时（临时 bootstrap 看似卡住）
- 使用前先退出 Hopper 主程序与 ExternalAPI；`close_binary` 后同样退出，保证下一次冷启动
- Hopper 6.1.0-demo 冷启动可用（实测 `/bin/ls` 133 procedures）；若出现 demo/license 对话框，先处理再重试

## Ghidra 12.1.4（REA 6.8.0 固定验证；系统 12.2 保持更新）

- 安装路径：`/Users/ahogek/.local/share/ghidra/ghidra_12.1.4_PUBLIC`；Homebrew `/opt/homebrew/opt/ghidra` 是 12.2，**不可**指向 REA
- REA 6.8.0 的 `SUPPORTED_GHIDRA_VERSION=12.1.4`；同 major.minor 可能标 compatible，不同 major/minor unsupported
- 原生反编译器已构建：`support/gradle/gradlew --no-daemon :Decompiler:buildNatives_mac_arm_64`，产物在 `Ghidra/Features/Decompiler/os/mac_arm_64/{decompile,sleigh}`
- `~/.omp/agent/mcp.json` 与 `~/.zprofile` 的 `GHIDRA_INSTALL_DIR` 均指向 12.1.4；改后重启 omp/MCP
- 版本漂移：用 Ghidra 前/至少每月跑 `npm view rea-agents version` + `doctor --provider ghidra --json`；新版支持新 Ghidra 时 side-by-side 安装，**不要** `brew upgrade ghidra` 后直接指过去
- Ghidra provider 不接受 universal Mach-O；先 `lipo -thin arm64/arm64e`。Hopper 可直接处理 universal
- 2026-10-29 实测：`doctor` healthy，`binary_session` provider 12.1.4；REA server expected skill 49，本地 skill 53 超前，以服务器 tool list 为准
