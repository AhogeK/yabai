# references — 空间 API 与实现对照表

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：已验证
> **来源**：SkyLight/DPPM API 与源码调用点逐项核对

## daemon → SA 能力对照

| daemon 调用 | opcode | payload 处理 | 依赖 |
|---|---|---|---|
| `scripting_addition_create_space(sid)` | `SPACE_CREATE` (0x03) | `do_space_create` | 创建入口（按代际）+ `dock_spaces`(G2) |
| `scripting_addition_destroy_space(sid)` | `SPACE_DESTROY` (0x04) | `do_space_destroy` | `remove_space_fp` + `dock_spaces` |
| `scripting_addition_focus_space(sid)` | `SPACE_FOCUS` (0x02) | `do_space_focus` | `dock_spaces` + SLS |
| `scripting_addition_move_space_*` | `SPACE_MOVE` (0x05) | `do_space_move` | `move_space_fp` + DPPM |

## SkyLight / CoreGraphics API

| API | 用途 |
|---|---|
| `SLSCopyManagedDisplayForSpace(cid, sid)` | sid → display UUID（主键来源） |
| `SLSCopyManagedDisplaySpaces(cid)` | 全部显示器与空间模型（daemon 状态刷新） |
| `SLSManagedDisplayGetCurrentSpace(cid, uuid)` | 显示器当前空间 |
| `SLSManagedDisplaySetCurrentSpace(cid, uuid, sid)` | 切换当前空间 |
| `SLSShowSpaces` / `SLSHideSpaces` | 空间显隐（切换动画/可见性） |
| `SLSGetSpaceManagementMode` | SIP 相关能力判定 |
| `CGDisplayCreateUUIDFromDisplayID(did)` | display id → UUID（沙箱安全） |
| `CGGetActiveDisplayList` / `CGMainDisplayID` | 本机显示器枚举 |
| （导入符号）`CGSMoveManagedSpaceToDisplayIndex` | 空间移动到显示器索引（Dock 内实现使用） |

## Dock 模型对象与方法（26/27 通用）

| 对象 | 方法 / 字段 |
|---|---|
| Spaces 单例（`dock_spaces`） | `spacesForDisplay:` / `currentSpaceForDisplayUUID:` / `currentSpaceForDisplay:` / `allUserSpaces` / `spaceWithUUID:` / `displayForSPID:` |
| DisplaySpaces（模型） | ivar `_displaySpaces`（数组）、每个 display_space 的 `_currentSpace` |
| ManagedSpace | `spid`、`displayUUID`、类型（user / fullscreen / proxy） |
| DPPM | `addSpace:forDisplayUUID:` / `removeSpace:` / `moveSpace:toDisplay:displayUUID:` / `addFullscreenSpace:forDisplayUUID:` |

## 空间布局的持久化位置（27.0.1）

| 路径 | 内容 |
|---|---|
| `~/Library/Preferences/com.apple.spaces.plist` | **系统空间布局存储**：`SpacesDisplayConfiguration → Management Data → Monitors[]`，每项含 `Display Identifier`（主屏为 `"Main"`）、`Current Space`、`Spaces[]`（`id64`/`type`/`uuid`） |
| `~/Library/Application Support/com.apple.windowmanager/state.plist` | 窗口分组状态（与空间无关） |
| `defaults read com.apple.windowmanager` | 仅 UI 偏好（无空间布局） |

**脏数据特征**：出现当前系统不存在的显示器 UUID（幽灵记录）；某显示器的 `Spaces` 重复同一 `id64` 或为空。

## SLS 空间模型的关键字段（27.0.1 实测）

| 字段 | 说明 |
|---|---|
| `SLSCopyManagedDisplaySpaces` | 每个元素 = 一个 display；`Display Identifier`、`Spaces[]`、`Current Space` |
| space 的 `id64` / `ManagedSpaceID` | yabai 用的 sid（实测两者一致，如 id=50/58） |
| space 的 `type` | 0 = user（27.0.1 上新建空间仍为 0） |
| space 的 `uuid` | **27.0.1 起等于其所在显示器的 UUID**（display 1 的两个空间都是 `37D8832A…`） |

yabai 的两个序号函数（`src/space_manager.c`）：`space_manager_mission_control_index(sid)` → 全局序号；`space_manager_mission_control_space(N)` → 反查。**两者都跨显示器累加**。

## 代际与系统版本对照

| 系统 | 创建 | 销毁 | 移动 | 备注 |
|---|---|---|---|---|
| ≤ 15 | Dock `addSpace` | Dock `removeSpace` | Dock `moveSpace` | pattern 按版本分段 |
| 26.0–26.6 | Dock Swift `space_create_entry`（26.0 `0x1f07d8`；26.6 `0x1f07d4`） | Dock `removeSpace` | Dock `moveSpace` | `dock_spaces` 双路定位 |
| **27.0** | **Dock 内部 helper `0x2bb62c`（G3′，已实现）**；`WindowManager.framework` 的 `synchronouslyRequestCreateManagedSpace`（G3，断言门不可用） | Dock `removeSpace`（pattern 命中 0x18b9a0） | Dock `moveSpace`（0x18c554） | 创建不再依赖 Dock 偏移 |

入口地址/基线与单例全局见 `dock-reverse-engineering/references.md`。
