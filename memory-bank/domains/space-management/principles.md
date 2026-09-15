# principles — 空间管理的不变量

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：含推论
> **来源**：§1 代际表已验证（26/27 实测）；§4 ivar 改名与 §5 前置门为源码推论，未在 27 实测

## 1. 空间创建有三代实现，daemon 接口恒定

| 世代 | 系统 | 实现 | 关键点 |
|---|---|---|---|
| G1 | ≤ 25 | Dock `addSpace` 函数 | `x0` = new_space、`x20` = display_space（insert-after 语义） |
| G2 | 26.x | Dock 内 Swift `space_create_entry` | `x0` = display_id、`x20` = Spaces 单例；入口随版本漂移（26.6 → `0x1f07d4`） |
| G3 | **27+** | `WindowManager.framework`：`synchronouslyRequestCreateManagedSpace(displayUUID:)` | 框架导出符号（dlsym），`x20` = WM 实例、`x0/x1` = UUID 字符串、`x21` = 错误、返回新 spid |
| G3′ ✅yabai 端到端实测 | **27+（唯一可用）** | Dock 内 Swift helper（与 WindowManager.app 同源同形）：`helper(cid, flags, type, displayUUID, pids) → CGSSpaceCreate` | Dock 自己的连接 id（懒加载 getter）+ 自建 options 字典；**不经过 admin XPC，无断言门**。G3 的同代 API 因 `layoutControlHolder` 断言对 Dock 不可得而失败 |

对新系统一律**先判断当前属于哪一代**，再决定改偏移还是换 API；不要默认"还是老机制"。

## 2. display UUID 是空间操作的唯一主键

空间创建/移动/壁纸同步都按显示器 UUID 绑定：`SLSCopyManagedDisplayForSpace()` 取 UUID → 传给目标 API；`CGDirectDisplayID`（`CGMainDisplayID` / `CGGetActiveDisplayList`）仅用于本机比对。**禁止**用 display index 做跨 API 传递。

## 3. 创建成功的不变量

新空间创建后必须在 `[Spaces spacesForDisplay:<uuid>]` 中出现且 `spid` 有效；否则视为失败（即使 API 返回成功）。

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
