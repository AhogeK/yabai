# meta — 空间管理（space）

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：环境基线
> **来源**：`src/space_manager.c` / `src/osax/payload.m` 源码核对

## 边界

yabai 的"桌面/空间"生命周期与切换行为：

- 创建 / 销毁 / 移动（跨显示、调整顺序）/ 聚焦（切换当前空间）
- 显示（display）与空间的绑定关系（display UUID 是主键）
- 空间状态在 Dock 模型（`Spaces` / `DisplaySpaces`）与 SkyLight（SLS/CGS）之间的同步

**不属于本领域**：Dock 内部函数怎么定位（→ `dock-reverse-engineering/`）、SA 协议怎么传（→ `scripting-addition/`）、窗口本身的布局（→ `systemPatterns.md` 窗口树 / `window_manager.c`）。

## 代码入口

| 位置 | 内容 |
|---|---|
| `src/space_manager.c` | daemon 侧空间操作入口（`space_manager_add_space` / `destroy_space` / `move_space_*` / 切换） |
| `src/mission_control.c` | Mission Control 状态判定（部分操作在 MC 激活时被拒绝） |
| `src/osax/payload.m` | `do_space_create` / `do_space_destroy` / `do_space_focus` / `do_space_move` |
| `src/osax/arm64_payload.m` | 空间相关函数入口与 pattern 基线 |
| `src/display_manager.c` | 显示器与空间的映射、动画态判定 |

## 术语

| 术语 | 含义 |
|---|---|
| **spid** | SkyLight 的 space id（`[space spid]`） |
| **display UUID** | 显示器 UUID 字符串（如 `37D8832A-…`），所有空间 API 的绑定键 |
| **display_space** | Dock 模型里"某显示器的空间集合"对象（含 `_currentSpace`） |
| **user space / fullscreen space** | 用户桌面 vs 全屏空间；多数操作只对 user space 有效 |
| **DPPM** | 壁纸管理器（`WallpaperAgentDesktopPictureManager`），空间增删需同步通知 |
| **代际** | 空间创建实现的三代演进（见 `principles.md` §1） |

## 环境

| 项目 | 值 |
|---|---|
| 当前系统 | macOS 27.0 (26A428)，Dock 2571.0.6.402 |
| 空间数据源 | `SLSCopyManagedDisplaySpaces` / `SLSManagedDisplayGetCurrentSpace` / `SLSCopyManagedDisplayForSpace` |
| 切换动作 | `SLSShowSpaces` / `SLSHideSpaces` / `SLSManagedDisplaySetCurrentSpace` |
| 多显示器 UUID | `CGDisplayCreateUUIDFromDisplayID`（IOKit 在 Dock 沙箱内不可用） |

## 别名与易混概念

| 易混对 | 区分 |
|---|---|
| space / desktop / 桌面 | 同一概念：yabai 命令与 SLS 用 space，UI 与用户口语用 desktop/桌面 |
| spid / sid / space_id | 同一个值：`spid` 是 SkyLight 侧的叫法（`[space spid]`），yabai 侧叫 sid/space_id |
| display UUID / CGDirectDisplayID | UUID 是跨进程跨 API 的字符串主键（如 `37D8832A-…`）；`CGDirectDisplayID` 是本机整型 id，**仅用于比对**，不跨 API 传递 |
| Spaces（单例） / ManagedSpace | Spaces = Dock 的空间管理器单例（= `dock_spaces`）；ManagedSpace = 单个空间对象（含 spid/displayUUID） |
| DisplaySpaces / display_space | 前者是 Dock 模型容器（ivar `_displaySpaces` 数组）；后者指数组中"某显示器的空间集合"对象（含 `_currentSpace`） |
| user space / fullscreen space | 用户桌面 vs 全屏空间；多数空间操作只对 user space 有效 |
| DPPM / Wallpaper | DPPM = `WallpaperAgentDesktopPictureManager`，负责空间↔壁纸绑定；"壁纸"是它管理的资源 |
| 空间切换 / 空间聚焦 | 同一动作：yabai `space --focus`、SLS `SetCurrentSpace` 与 Swift `switchToUserSpace:` 指同一语义 |
