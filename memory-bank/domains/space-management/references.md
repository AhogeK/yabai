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

## 代际与系统版本对照

| 系统 | 创建 | 销毁 | 移动 | 备注 |
|---|---|---|---|---|
| ≤ 15 | Dock `addSpace` | Dock `removeSpace` | Dock `moveSpace` | pattern 按版本分段 |
| 26.0–26.6 | Dock Swift `space_create_entry`（26.0 `0x1f07d8`；26.6 `0x1f07d4`） | Dock `removeSpace` | Dock `moveSpace` | `dock_spaces` 双路定位 |
| **27.0** | **`WindowManager.framework`** | Dock `removeSpace`（pattern 命中 0x18b9a0） | Dock `moveSpace`（0x18c554） | 创建不再依赖 Dock 偏移 |

入口地址/基线与单例全局见 `dock-reverse-engineering/references.md`。
