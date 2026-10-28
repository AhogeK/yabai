# principles — 空间管理的不变量

> **系统基线**：macOS 27.2 (26B123) · Dock 2571.1.32.402 · WindowManager 462.1.41.404
> **最后验证**：2026-10-28 · **状态**：已验证（27.2 真机 create/focus/move/排序/destroy）
> **来源**：代际表 26/27 实测；§4 ivar 改名与 §5 前置门为源码推论，未在 27.2 实测

## 1. 空间创建有三代实现，daemon 接口恒定

| 世代 | 系统 | 实现 | 关键点 |
|---|---|---|---|
| G1 | ≤ 25 | Dock `addSpace` 函数 | `x0` = new_space、`x20` = display_space（insert-after 语义） |
| G2 | 26.x | Dock 内 Swift `space_create_entry` | `x0` = display_id、`x20` = Spaces 单例；入口随版本漂移（26.6 → `0x1f07d4`） |
| G3 | **27+** | `WindowManager.framework`：`synchronouslyRequestCreateManagedSpace(displayUUID:)` | 框架导出符号（dlsym），`x20` = WM 实例、`x0/x1` = UUID 字符串、`x21` = 错误、返回新 spid |
| G3′ ✅yabai 端到端实测 | **27+（唯一可用）** | Dock 内 Swift helper（与 WindowManager.app 同源同形）：`helper(cid, flags, type, spaceUUID, pids) → CGSSpaceCreate` | 第 4 参数是**新空间身份**（原样进 `CGSSpaceCreate` options 的 `uuid`），必须传新生成的 UUID；显示器 UUID 只用于创建后校验落点。Dock 自己的连接 id（懒加载 getter）+ 自建 options 字典；**不经过 admin XPC，无断言门**。G3 的同代 API 因 `layoutControlHolder` 断言对 Dock 不可得而失败 |

对新系统一律**先判断当前属于哪一代**，再决定改偏移还是换 API；不要默认"还是老机制"。

## 1.5 yabai 的 index 是「全局序」—— 27.2 起与 Mission Control 重新一致

`query --spaces` 的 `index`、以及 `space --focus N` / `window --space N` 里的 N，都是跨显示器顺序累加（`space_manager_mission_control_index` 用一个走到头的 `desktop_cnt`）。

- **macOS 27.2（26B123，2026-10-28 用户实测）**：Mission Control 已恢复**全局编号**（三台显示器连续 Desktop 1/2/3）→ 直接 `space --focus N` 与看到的 Desktop N 一致；
- 27.0.1 曾改为每显示器独立编号（历史见 `scenarios.md` S8）；当时“按当前显示器取第 N 个”的写法已**不再需要**；
- 绑定层已回滚：`~/.config/skhd/skhdrc` 直接使用 N（备份 `skhdrc.bak-20261028-global-index`）；
- **不要**改 yabai 的 index 语义（上游定义 + 破坏既有脚本）；系统若再次改变编号，先实测再调整绑定。

## 2. display UUID 用于绑定，空间身份必须唯一

- **移动/壁纸同步**按显示器 UUID 绑定：`SLSCopyManagedDisplayForSpace()` 取 UUID → 传给目标 API；`CGDirectDisplayID` 仅用于本机比对。**禁止**用 display index 做跨 API 传递。
- **创建**时 Dock helper 的第 4 个参数是**新空间身份**，不是显示器绑定：传入什么字符串，`CGSSpaceCreate` 就把它写成该空间的 `uuid`。必须每次生成新 UUID（与系统 “+” 一致）；传显示器 UUID 会让同显示器所有空间共享身份。

## 3. 创建成功的不变量

- 新空间创建后必须在 `[Spaces spacesForDisplay:<uuid>]` 中出现且 `spid` 有效；否则视为失败（即使 API 返回成功）。
- **身份唯一**：同一显示器上不得存在两个 `uuid` 相同的空间。`com.apple.spaces` 按身份持久化；开机恢复时重复身份全部映射到同一 `id`，表现为 `managed space order: [6,6,…]`、Mission Control 只剩一个桌面、壁纸丢失。实测：系统 “+” 的空间 `uuid=442D311F…` 唯一，而 7.2.5 及以前由 yabai 创建的空间 `uuid` = 显示器 UUID。

## 4. 切换空间要同时动 SLS 与 Dock 模型

`SLSManagedDisplaySetCurrentSpace` 只切 SkyLight；Dock 模型（`DisplaySpaces._currentSpace`）需同步，否则菜单栏/Mission Control 显示与实际不一致。旧 ivar 名（`_displaySpaces` / `_currentSpace`）在新系统上**可能已被改名** `[推论]`：`object_getInstanceVariable` 取不到时为 nil，此时 SLS 切换仍生效 → **模型回写失败只降级，不得中断切换**。

## 5. 空间操作有前置状态门

Mission Control 激活中、显示器动画中、目标不是 user space（如全屏空间）时，daemon 会直接拒绝（`SPACE_OP_ERROR_*`）。排查"命令没反应"时先确认这些前置条件，而不是先怀疑 SA。

## 6. 空间增删要通知 DPPM

Dock 模型里的壁纸归属由 DPPM 维护（`addSpace:forDisplayUUID:` / `removeSpace:` / `moveSpace:toDisplay:displayUUID:`）。**只调 SLS/Spaces 而不通知 DPPM** → 空间存在但壁纸错位/空白。

## 7. 代际切换期的双保险

新入口不可用时保留可回退路径（26 的 `dock_spaces` 有 pattern + DOUBLE-ANCHOR 两路；27 的创建走框架而 `removeSpace`/`moveSpace` 仍走 Dock 内函数），但**每个路径都要独立可判失败**（显式 0 + 日志），不得静默降级到语义不同的实现。

## 8. macOS 27：变更是"断言制"，不是随意调用

WindowManager 的 AdminXPC 连接是**断言模型**（`AdminXPCConnectionError.Kind`：`assertionNotHeld` / `assertionAlreadyHeld` / `missingEntitlement` / `invalid` …）。Dock 自身的变更协议是：

```
synchronouslyRequestLayoutControl()  → 若需变更则先拿到 control 对象（= 持有断言）
  → 执行变更（窗口激活 / 空间操作）
  → synchronouslyCommitPendingUpdates()
  → 释放 control（deinit 归还断言）
```

**实测**：不做第 1 步直接调 `synchronouslyRequestCreateManagedSpace` → 抛错（error != 0，`x0` 为未定义的垃圾值，**不可当 spid 使用**）`[推论]`：错误类型推断为 `assertionNotHeld`，待实测确认。

**调用注意**：control 对象是 **+1 所有权**（Dock 的用法：`str xN, [ivar]` 无 retain、随后 `swift_release` 旧值），用完必须 `swift_release`；**泄漏它等于永久占住断言**，会让后续变更报 `assertionAlreadyHeld`。
