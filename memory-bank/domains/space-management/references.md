# references — 空间 API 与实现对照表

> **系统基线**：macOS 27.2 (26B123) · Dock 2571.1.32.402 · WindowManager 462.1.41.404
> **最后验证**：2026-10-28 · **状态**：已验证（真机 create/focus/move/排序/destroy）
> **来源**：`src/osax/payload.m` 调用形态 + 27.2 运行日志

## daemon → SA 能力对照

| daemon 调用 | opcode | payload 处理 | 依赖（27.2） |
|---|---|---|---|
| `scripting_addition_create_space(sid)` | `SPACE_CREATE` (0x03) | `do_space_create` | Dock helper `0x20ce00` + Swift String 桥 + 空数组槽 `0x2ef0d8` |
| `scripting_addition_destroy_space(sid)` | `SPACE_DESTROY` (0x04) | `do_space_destroy` | `CGSSpaceDestroy(cid, sid)` |
| `scripting_addition_focus_space(sid)` | `SPACE_FOCUS` (0x02) | `do_space_focus` | Spaces 单例槽 `0x329be0` + `SLSManagedDisplaySetCurrentSpace` |
| `scripting_addition_move_space_*` | `SPACE_MOVE` (0x05) | `do_space_move` | 跨屏 `CGSMoveManagedSpaceToDisplayIndex`；排序 `SLSTransaction*` |

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
| `CGSSpaceDestroy(cid, sid)` | 删除托管空间（27.2 Dock 内调用形态已核对） |
| `CGSMoveManagedSpaceToDisplayIndex(cid, sid, displayUUID, flags)` | 跨显示器移动空间 |
| `SLSTransactionCreate(cid)` / `SLSTransactionMoveManagedSpaceToDisplayAfterSpace(tx, sid, uuid, afterSid)` / `SLSTransactionCommit(tx, 1)` | 同显示器排序（事务） |

## Dock 模型对象与方法（26/27 通用）

| 对象 | 方法 / 字段 |
|---|---|
| Spaces 单例（`dock_spaces`） | `spacesForDisplay:` / `currentSpaceForDisplayUUID:` / `currentSpaceForDisplay:` / `allUserSpaces` / `spaceWithUUID:` / `displayForSPID:` |
| DisplaySpaces（模型） | ivar `_displaySpaces`（数组）、每个 display_space 的 `_currentSpace` |
| ManagedSpace | `spid`、`displayUUID`、类型（user / fullscreen / proxy） |
| DPPM | `addSpace:forDisplayUUID:` / `removeSpace:` / `moveSpace:toDisplay:displayUUID:` / `addFullscreenSpace:forDisplayUUID:` |

## daemon 日志落点与"写进已删除 inode"陷阱

| 项 | 值 |
|---|---|
| launchd plist | `~/Library/LaunchAgents/com.asmvik.yabai.plist` |
| stdout / stderr | `/tmp/yabai_<user>.out.log` / `/tmp/yabai_<user>.err.log` |
| 陷阱 | 若日志文件被删（如重装/清理），daemon 仍持旧 fd → 新事件写进**已删除 inode**，文件大小恒为 0（`lsof -p <pid>` 可见 fd 指向该路径但 `ls` 不存在） |
| 恢复 | 重启 daemon（`yabai --restart-service`）后文件重建 |
| 事件可见性 | 需 `yabai -m config debug_output on`（重启后默认关闭，不会自动继承） |

## 空间布局的持久化位置（27.0.1）

| 路径 | 内容 |
|---|---|
| `~/Library/Preferences/com.apple.spaces.plist` | **系统空间布局存储**：`SpacesDisplayConfiguration → Management Data → Monitors[]`，每项含 `Display Identifier`（主屏为 `"Main"`）、`Current Space`、`Spaces[]`（`id64`/`type`/`uuid`） |
| `~/Library/Application Support/com.apple.windowmanager/state.plist` | 窗口分组状态（与空间无关） |
| `defaults read com.apple.windowmanager` | 仅 UI 偏好（无空间布局） |

**脏数据特征**：出现当前系统不存在的显示器 UUID（幽灵记录）；某显示器的 `Spaces` 重复同一 `id64`、为空，或多个条目共享同一 `uuid`（开机恢复会全部塌缩到同一 id）。

## SLS 空间模型的关键字段（27.0.1 实测）

| 字段 | 说明 |
|---|---|
| `SLSCopyManagedDisplaySpaces` | 每个元素 = 一个 display；`Display Identifier`、`Spaces[]`、`Current Space` |
| space 的 `id64` / `ManagedSpaceID` | yabai 用的 sid（实测两者一致，如 id=50/58） |
| space 的 `type` | 0 = user（27.0.1 上新建空间仍为 0） |
| space 的 `uuid` | 7.2.6 前 yabai 创建的空间**误用显示器 UUID**（同屏多空间身份重复，开机塌缩）；7.2.6 起每次传新 UUID，系统 “+” 亦如此。27.2 真机验证 id 唯一 |

yabai 的两个序号函数（`src/space_manager.c`）：`space_manager_mission_control_index(sid)` → 全局序号；`space_manager_mission_control_space(N)` → 反查。**两者都跨显示器累加**。

## 代际与系统版本对照

| 系统 | 创建 | 销毁 | 移动 | 备注 |
|---|---|---|---|---|
| ≤ 15 | Dock `addSpace` | Dock `removeSpace` | Dock `moveSpace` | pattern 按版本分段 |
| 26.0–26.6 | Dock Swift `space_create_entry`（26.0 `0x1f07d8`；26.6 `0x1f07d4`） | Dock `removeSpace` | Dock `moveSpace` | `dock_spaces` 双路定位 |
| **27.0** | **Dock 内部 helper `0x2bb62c`（G3′）**；`WindowManager.framework` 的 `synchronouslyRequestCreateManagedSpace`（G3，断言门不可用） | Dock `removeSpace`（0x18b9a0） | Dock `moveSpace`（0x18c554） | 27.0 实测可用；27.2 重编译后失效 |
| **27.2** | **Dock helper `0x20ce00`（构建锁定 + 段校验）** | `CGSSpaceDestroy` | `CGSMoveManagedSpaceToDisplayIndex` / `SLSTransaction*` | 旧 pattern 全 0 命中；`remove_space` 伪命中 0x12dbcc |

## 全屏还原状态（daemon 内部，7.2.x）

| 项 | 位置 | 说明 |
|---|---|---|
| `pending_fullscreen_sid` / `pending_fullscreen_src_sid` | `window_manager` | 已捕获的全屏空间与其来源空间 |
| `view_follow_sid` / `view_follow_window_id` / `view_follow_generation` / `view_follow_abort` | `window_manager` | 视图跟随意图：目标空间 / 待聚焦窗口 / 世代号（作废兜底定时器）/ 放弃标记 |
| `VIEW_FOLLOW_FALLBACK_SECONDS` / `VIEW_FOLLOW_FOCUS_DELAY_SECONDS` | `window_manager.h` | 0.4 秒兜底补切 / 150 ms 后聚焦窗口 |
| `window_manager_arm_view_follow()` / `_view_follow_on_space_change()` / `_view_follow_focus_window()` / `_abort_view_follow()` / `_view_follow_fire()` / `_view_follow_window()` | `window_manager.c` | 登记 / 空间变化只聚焦窗口 / 排延迟聚焦 / 让位 / 兜底补切（事件循环线程）/ 聚焦窗口 |
| `VIEW_FOLLOW` / `VIEW_FOLLOW_WINDOW` 事件 | `event_loop.h` 类型表 + `event_loop.c` 处理器 | 把两步从主线程投递到事件循环线程 |
| `space_is_visible(sid)` | `space.h` 声明 / `space.c` 内联 | `sid == display_space_id(space_display_id(sid))`，按该空间所属显示器判断 |

入口地址/基线与单例全局见 `dock-reverse-engineering/references.md`。
