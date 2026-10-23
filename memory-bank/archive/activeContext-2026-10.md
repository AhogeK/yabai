> 冷数据归档（R12）。仅供回溯，不再更新。

## 快照 2026-10-10 04:45（7.2.1 视图跟随修复时压缩前的 activeContext 全文）

# Active Context - yabai

## Current Work Focus

**7.2.0「全屏记忆」事故 → 已回退（2026-10-10）**

- 现象：装 7.2.0 后 daemon 崩溃循环（~10s/次）+ 系统卡
- 根因：`window_manager_remember_geometry` 对 `space_window_list()` 的池内存调 `free()` → libmalloc abort
- 止损：回退 HEAD(7.1.29)+重装；运行中进程仍需 `yabai --restart-service` 换回
- 现场：`/tmp/fullscreen-restore-7.2.0.patch`；**修正版已去 free（2 处）+ 改用只读 `space_manager_query_view`，双架构 0 告警，已安装为 7.2.0（04:13），待重启+复现验证**；教训见 `systemPatterns.md`

**当前焦点**：macOS 27.0.1 系统侧空间恢复问题排查（见下）；7.1.29 已发布，创建/销毁/聚焦正常 (2026-10-10)

### 🐞 系统侧空间恢复问题 x2（27.0.1）

- **开机主屏无桌面**：WindowManager 日志 `managed space order: [6,6,6,6,6,6,6,6]`（主屏损坏）+ 反复 `No visible space found for display: 37D8832A-…; skipping`；`com.apple.spaces.plist` 含幽灵显示器 `F03C6F6E-…`；`space --create` 可修；daemon 开机以来 create/destroy 次数 = 0
- **全屏退出窗口回落 desktop 1**：全屏空间（id 1526）销毁后系统直接 `SPACE_CHANGED: 50`（= display1 index1），期间无任何 `window --space` 命令
- **yabai 搬移路径已穷举**：命令（日志未现）、规则（无 space 规则）、daemon 自动指派（死代码）、SA（无该 opcode）→ 两件都不是 yabai
- **处置**：清幽灵记录/复位 `com.apple.spaces`（见 S9）；全屏那条若要绕过需行为 hack（记忆并送回），待决定 [系统侧机械为推论]

### 🔎 系统更新后核查（27.0.1 / 26A434，2026-09-30）

- **SA 与创建路径仍正常**：Dock 版本未变（2571.0.6.402），pattern 命中不变；日志显示当天两次成功创建（space id 50 / 57）
- **yabai 核心操作正常**：`space --focus 3` 精确落在 display 2 的空间，模型分组与 SLS 原始模型一致
- **唯一错位**：yabai 的 `index` / 数字选择器是**全局序**，而 macOS 27.0.1 的 Mission Control 按**每显示器独立**编号 → 多显示器下 `focus N` 与"看到的 Desktop N"不一致（详见 space-management/principles.md §1.5 与 scenarios.md S8）
- 处置：**不改 yabai**（上游语义 + 自洽），在绑定层用 `query --spaces --display` 取"当前显示器的第 N 个"

### ✅ macOS 27 空间创建已修好（7.1.29，2026-09-15 yabai 端到端实测通过）

**最终机制（G3′）**：调用 Dock 自己的 Swift 创建 helper（pattern 0x2bb62c）——
`helper(cid, flags=0, type=0, SwiftString(displayUUID), __swiftEmptyArrayStorage) → 新空间 id`

**独立验证（脱离 yabai，最小注入负载 `/tmp/spacetest/minpay.dylib`）**：

```
[minpay] A displayUUID -> 0xcd   spaces 9 -> 10    ← 成功
[minpay] DONE spaces 9 -> 10                      ← yabai query 确认 10 个空间，Dock 未崩
```

**两个被推翻的假设**（别再走回头路）：

1. **不是 cid 问题**：`[dockConnection]` 实测 == `SLSMainConnectionID()`（1919... 相同）
2. **不是 uuid 语义问题**：显示器 UUID 即可（Dock 自身 0x1744cc 用随机 UUID 属另一条路径）

**真正的三个坑（都有崩溃样本）**：

| 坑 | 症状 | 正解 |
|---|---|---|
| 签名状态与分支指令不配对 | `PAC_EXCEPTION`（两个方向都出现过） | 未签名裸地址→`blr`；**已签名指针（remove/move/setFrontWindow/addSpace）→ C 调用**；dlsym→`blraaz`。曾把 removeSpace 统一改成 `blr`，27 实测崩在 destroy |
| `dlsym("__swiftEmptyArrayStorage")` = NULL | 崩在 helper 内 `[NULL+0x10]` | 从 literal pool 解码（site pattern 0x1744bc → slot **0x3c3998**）；**取不到就不调用** |
| image 相对 offset 加错基址 | 崩在 `slide+0x2c0000` | 加在 **header 指向的运行时地址**上 |

**为什么必须在 Dock 内**（实测）：普通进程 `CGSSpaceCreate` 四种参数全 NULL；非 Dock 进程调框架 API 报 *"Couldn't communicate with a helper application."*

**yabai 端到端证据（2026-09-15 19:50，SA 重载后）**：

```
[yabai-sa][SPACE] dock connection-id getter found (0x10064AAA8)
[yabai-sa][SPACE] dock space-create helper found (0x10064362C)
[yabai-sa][SPACE] empty pid array singleton = 0x1f9ea7db8 (call site 0x1004FC4BC, slot 0x10074B998)
[yabai-sa][SPACE] dock space-create helper returned space id 213
spaces 10 -> 11
```

**`space --destroy` 未动态验证**：daemon 侧被 `space_manager_is_space_last_user_space` 拦下（"acting space is the last user-space..."），请求未到 payload；该路径本次只改了分支指令（`blr`），参数/ABI 沿用 26 代已验证版本。

**清理教训（本轮踩到）**：大批删代码后只验证"编译 + 无告警 + pattern 命中"不够——必须核对**数据流**（关键全局量的赋值点是否还在）。本轮就是删 WM 块时把同段的 G3′ 解析代码一起删了，靠加载日志缺 3 行才发现。

## 📋 上一轮变更 (macOS 27 初版支持, 7.1.28)

**版本**: 7.1.27 → **7.1.28**，OSAX_VERSION 2.1.31 → **2.1.32**

**环境**: macOS 27.0 (26A428)，Dock **2571.0.6.402**，WindowManager.framework 462.0.8

**根因**（两条同时存在）:
1. `verify_os_version()` 没有 majorVersion 27 分支 → `init_instances()` 直接 return，**所有 SA 功能全灭**（这是"再次失效"的直接原因）
2. macOS 27 Dock **删除了 Swift 空间创建入口**（26.6 的 `0x1f07d4`），空间管理下沉到 `WindowManager.framework`

**修复内容**:
- `src/osax/payload.m`
  - `verify_os_version()` 增加 27 分支（x86_64 分支不加，27 无 Intel）
  - 新增 WindowManager 符号解析（`init_instances`，majorVersion ≥ 27）:
    `$s13WindowManagerAACMa` / `...6sharedABvgZ` / `...CreateManagedSpace...tKF` /
    `$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ` / `swift_errorRelease`
  - `do_space_create()` 新增 27 路径：Swift ABI 调用
    `WindowManager.shared.synchronouslyRequestCreateManagedSpace(displayUUID:)`
    （x20=self，x0/x1=Swift String，x0=新 spid，**x21=swift_error***）
  - 新增 3 个 asm 宏 + `swift_string_t`
  - 握手属性 `OSAX_ATTRIB_ADD_SPACE` 改为 `add_space_fp || space_create_entry_fp || wm_create_space_fp`
  - DPPM 指纹兜底块加 `dp_desktop_picture_manager == nil` 判定（27 上指纹已失效，避免误报 ERROR）
- `src/osax/arm64_payload.m`：全部 `get_*_offset/pattern` 增加 27 分支
  - dock_spaces 0x30000（pattern 不变，命中 0x30a98 → 全局 0x100409bb0）
  - dppm **0x40000**（旧 0x70000 会错过 0x509fc → 全局 0x100409c50）
  - remove_space / move_space **0x180000**（命中 0x18b9a0 / 0x18c554）
  - fix_animation **0x220000**（命中 0x227508）
  - set_front_window 0x10000 + **新 pattern**（首 4 字节改通配）→ 唯一命中 0x192bc
  - add_space / space_create_entry → 0（27 无 Dock 内实现）

**验证**: 静态 ✅（pattern 命中/唯一性/全局解码 + 双架构编译）；动态 ❌ **初版 7.1.28 实际不可用**——`space --create` 让 Dock 崩溃（PAC 调用问题，见上文 🔥），其余能力（dock_spaces/DPPM/removeSpace/moveSpace/setFrontWindow 解析）均正常

**文档**: `docs/reverse-engineering-macos27-space-create.md`（含 dyld cache 提取与 pattern 校验脚本）

**发布** (2026-09-15):
- ai-base `877e4b1` fix → `58edb26` bump 7.1.28 → `17318fb` AI 记忆
- dev `fbca387` → `0994274`（cherry-pick，无 AI 文件）；master `f2edcba` → `15ae877`（从 dev 逐级 pick）
- 三支已 push 至 origin，校验一致（src/osax 相同、dev/master 工作树相同、无 AI 文件）

---

## 🧭 规则优化 (2026-09-15)

对照 `../ctt-server/AGENTS.md` 重写本文件（R1-R18），补强四块：

- **R5 / R5.5 授权机械判定**：关键词表（提交≠推送≠pick）+ 执行前自检清单 + 「修好它 ≠ 提交」作用域闭合
- **R14 分支管理与提交拆分**：ai-base → dev → master 只能逐级 cherry-pick（禁 merge/rebase/反向 pick）+ 功能/版本/AI 记忆三段提交顺序 + 校验清单
- **R15 版本号管理**：五个版本号位置表（yabai.c / install.sh / common.h / CHANGELOG / yabai.1）+ 全局检查
- **R12 记忆冷归档**：修剪 = 归档而非删除（`memory-bank/archive/`）
- **R19 领域知识库**（补齐 R25 缺口）：新增 `memory-bank/domains/`，建 3 个领域（`dock-reverse-engineering` / `scripting-addition` / `space-management`），每领域五件套 `meta / principles / scenarios / practices / references` + `domains/README.md` 索引；同步把 `systemPatterns.md` / `techContext.md` 里的领域专属内容收敛为指针（R19「不得两处重复」）

**领域层落点**：

| 领域 | 承载的可复用判断 |
|---|---|
| `dock-reverse-engineering` | 稳定/不稳定字节判据、基线窗口语义（`0x1286a0` 首匹配）、单例识别三要素、系统升级适配七步流程、dyld cache 提取与语义画像脚本 |
| `scripting-addition` | 属性位必须与真实能力一致、payload 改动必 bump `OSAX_VERSION`、代际分流不改协议、注入/重启由用户执行、沙箱静默失败 |
| `space-management` | 空间创建三代实现表、display UUID 为主键、创建成功的不变量、SLS 与 Dock 模型双写、DPPM 通知 |

**二轮补强（参照《架构师 Agent / 知识库体系》方法论，2026-09-15）**：
- **R1 渐进式加载**：会话开始只读 `AGENTS.md` + 时间线层；领域文件按任务类型路由加载（新增路由表），并写明**回源原则**（binary 行为以实测为准 / 契约以源码为准 / 历史原因以 docs 为准）
- **R19 条目元数据（强制）**：每个领域文件头部标注 `系统基线 / 最后验证 / 状态（已验证·含推论·方法论） / 来源`；正文推论就地标 `[推论]`，不得把推断伪装成事实
- **R19 维护触发表**：macOS 大版本升级 → 全域复核；`arm64_payload.m` / `payload.m` / `common.h` / `sa.[hm]` / `space_manager.c` 改动 → 各自对应需复核的领域文件
- **R19 写回规则**：`docs/` 只作证据链，确认后的结论必须写回领域文件
- **meta 增「别名与易混概念」**：dock-RE（pattern/基线、入口/早退点、全局/单例、0 命中/不存在、Dock/DockCore/WindowManager）、SA（SA/osax、payload/loader、属性位/opcode、两个 socket、代际分流/协议变更）、space（space/desktop、spid/sid、UUID/CGDirectDisplayID、Spaces/ManagedSpace、user/fullscreen space）

## 已知设计限制 (不处理)

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字 (1秒覆盖) | Apple 未暴露相关 API，无完美解法 |

---

## 📚 历史锚点（macOS 26 世代）

- macOS 26 空间创建: `space_create_entry(displayID, Spaces self)`，调用约定 `x0=display_id, x20=Spaces`
- 26.6 入口 `0x1f07d4`；dock_spaces 双重保险（pattern + DOUBLE-ANCHOR 回溯 adrp/add）
- 逆向方法论沉淀: `docs/my-reverse-engineering-learn.md`、`docs/macos26/`
- 上游同步 30 commits (2026-04-26) → 版本 7.1.25，详见 `docs/upstream-sync-report-2026-04-26.md`
- Opacity 优化: `window_manager_enforce_rule_opacity()` 专用函数


---

## 快照 2026-10-10 05:05（7.2.2 重做时替换掉的 activeContext 全文）

# Active Context - yabai

## Current Work Focus

**7.2.1「视图跟随」修复（2026-10-10）— 编译通过，待实测**

- 目标：退出原生全屏后**视图**跟随窗口停在来源空间（7.2.0 只把窗口送回去了，视图被系统切回 desktop 1）
- 日志证据（7.2.0 实测，/tmp/yabai_ahogek.out.log）：`fullscreen restore: win=15973 -> space=58 (focus=0)` 之后紧跟 `EVENT_HANDLER_SPACE_CHANGED: 50`；序列 `50 → 58 → 50`（系统在收尾阶段**再次**把该显示器切回第一个 user space）
- 实现：
  - 还原段改为「记目标空间 + 截止时间 → 交统一入口」；新增 `window_manager_retry_pending_focus()`，从 `SPACE_CHANGED`（event_loop.c）与 `WINDOW_MOVED`/`WINDOW_RESIZED`（经 `window_manager_retry_fullscreen_entry`）调用
  - 判据 `space_is_visible(sid)`（按目标空间**所属显示器**判断，与焦点窗口在哪块屏无关）；武装**不因中间态解除**（否则 `50 → 58 → 50` 必输）；终止 = 3 秒到期（`FULLSCREEN_FOCUS_WINDOW_NS`）或 5 次重试（`FULLSCREEN_FOCUS_MAX_ATTEMPTS`）
  - 清理点：新进全屏（note）、来源空间销毁、超限、到期
- 版本：7.2.0 → **7.2.1**（PATCH）；`OSAX_VERSION` 不变（未动 payload）
- 证据：`make BUILD_PATH=/tmp/fsbuild` → 0 告警 0 错误；`/tmp/fsbuild/yabai --version` = `yabai-v7.2.1`，含新日志串
- 待办：部署 7.2.1 + 复现；判据见 `domains/space-management/scenarios.md` S10

**7.2.0「全屏记忆」事故 → 已回退重写（2026-10-10）**：`window_manager_remember_geometry` 对 `space_window_list()` 的池内存 `free()` → libmalloc abort 崩溃循环；修正版已去 free（2 处）+ 改用只读 `space_manager_query_view`；现场补丁 `/tmp/fullscreen-restore-7.2.0.patch`；教训见 `systemPatterns.md`

**当前焦点**：macOS 27.0.1 系统侧空间恢复问题排查（见下）

### 🐞 系统侧空间恢复问题 x2（27.0.1）

- **开机主屏无桌面**：WindowManager 日志 `managed space order: [6,6,6,6,6,6,6,6]`（主屏损坏）+ 反复 `No visible space found for display: 37D8832A-…; skipping`；`com.apple.spaces.plist` 含幽灵显示器 `F03C6F6E-…`；`space --create` 可修；daemon 开机以来 create/destroy = 0
- **全屏退出窗口回落 desktop 1**：全屏空间销毁后系统直接 `SPACE_CHANGED: 50`（= display1 index1），期间无 `window --space` 命令；yabai 侧搬移路径已穷举（命令 / 规则 / 自动指派死代码 / SA 无该 opcode）→ 系统侧行为；**绕过已实现（7.2.1）**
- **处置**：清幽灵记录 / 复位 `com.apple.spaces`（见 S9）

### 🔎 系统更新后核查（27.0.1 / 26A434，2026-09-30）

- SA 与创建路径正常（Dock 2571.0.6.402，pattern 命中不变，当天两次成功创建）
- yabai 核心操作正常；唯一错位 = yabai 的 `index` 是**全局序**，27.0.1 Mission Control 按**每显示器独立**编号 → 多显示器下 `focus N` 与"看到的 Desktop N"不一致（`domains/space-management/` §1.5 / S8）；处置：不改 yabai，绑定层用 `query --spaces --display` 取当前显示器第 N 个

### ✅ macOS 27 空间创建已修好（7.1.29，2026-09-15 端到端实测通过）

- 机制（G3′）：调用 Dock 自己的 Swift 创建 helper（pattern 0x2bb62c）`helper(cid, 0, 0, SwiftString(displayUUID), __swiftEmptyArrayStorage) → 新 spid`；完整逆向见 `docs/reverse-engineering-macos27-space-create.md`，领域结论见 `domains/scripting-addition/`、`domains/dock-reverse-engineering/`
- 最小注入取证（`/tmp/spacetest/minpay.dylib`）：`A displayUUID -> 0xcd`，spaces 9 → 10，Dock 未崩
- 两个被推翻的假设：**不是 cid 问题**（`[dockConnection]` == `SLSMainConnectionID()`）；**不是 uuid 语义**（显示器 UUID 即可，随机 UUID 属另一路径）
- 三个坑：签名状态与分支指令配对（未签名裸地址→`blr`；已签名指针 remove/move/setFrontWindow/addSpace→C 调用；dlsym→`blraaz`）；`__swiftEmptyArrayStorage` 不可 dlsym（literal pool slot `0x3c3998` 解码，取不到就不调用）；image 相对 offset 要加在 header 指向的运行时地址
- `space --destroy` 未动态验证（daemon 侧被 last-user-space 拦下，请求未到 payload）
- 清理教训：大批删代码后必须核对**数据流**（关键全局量赋值点是否还在），只验"编译 + pattern 命中"不够

### 📋 更早变更（7.1.28 macOS 27 初版支持，2026-09-15，全文见归档）

- `payload.m`：`verify_os_version()` 加 27 分支（无它则 SA 全灭）；27 路径改走 WindowManager Swift 符号；握手属性 `OSAX_ATTRIB_ADD_SPACE` 兼容三者；DPPM 指纹兜底加 `nil` 判定
- `arm64_payload.m`：各 `get_*_offset/pattern` 加 27 分支（dock_spaces 0x30000 / dppm 0x40000 / remove+move 0x180000 / fix_animation 0x220000 / set_front_window 新 pattern 命中 0x192bc；add_space 与 space_create_entry 27 无实现 → 0）
- 结果：初版 7.1.28 的 `space --create` 让 Dock 崩（PAC，见上）；7.1.29 修正
- 发布（2026-09-15）：ai-base `877e4b1` → `58edb26` → `17318fb`；dev `fbca387` / `0994274`；master `f2edcba` / `15ae877`（逐级 cherry-pick，三支已 push）

### 🧭 规则体系（2026-09-15 重写，正文见 `AGENTS.md`）

- R5/R5.5 授权机械判定（提交≠推送≠pick + 执行前自检）· R14 三级 cherry-pick + 功能/版本/记忆三段提交 · R15 五处版本号 · R12 冷归档 · R19 领域知识库（3 领域 × 五件套 + 条目元数据 + 维护触发表）

## 已知设计限制 (不处理)

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字 (1秒覆盖) | Apple 未暴露相关 API，无完美解法 |

---

## 📚 历史锚点

- macOS 26 世代（空间创建入口 `0x1f07d4`、dock_spaces 双重保险、上游同步 30 commits → 7.1.25、opacity 优化 `window_manager_enforce_rule_opacity()`）：细节已归档 `archive/activeContext-2026-10.md`，领域结论见 `domains/`


---

## 快照 2026-10-10 05:20（7.2.3 时替换掉的 activeContext 全文）

# Active Context - yabai

## Current Work Focus

**7.2.2「视图跟随」重做：只切一次（2026-10-10）— 编译通过，待实测**

- **7.2.1 的"重试抢回"被实测否掉**：日志里每一次 `SPACE_CHANGED: 50` 之前都紧跟一条客户端命令 `space --focus 1`（你的 front-switch 脚本或按键），重试只是与它互相放大 → 反复闪回；daemon 自己调 `space_manager_focus_space()` 不会出现在 `DAEMON_MESSAGE`，据此可把"系统偷偷复位"和"外部驱动"分开
- 新设计（`window_manager.c` + `event_loop.c` + `message.c`）：
  - 把窗口送回来源空间时只**登记一次**跟随意图（`view_follow_sid` + 3 秒总限期）
  - 每个 `SPACE_CHANGED` 把切换**推迟 0.5 秒**（世代号作废旧定时器）→ 安静下来才切，**只切一次、不重试**
  - 收到**外部空间/窗口切换命令**（`space …`、`window --focus/--space/--display`）立刻放弃 → 你在操作桌面时绝不插手
  - 实际切换投递到事件循环线程执行（新事件类型 `VIEW_FOLLOW`），主线程只做校验
- 版本：7.2.1 → **7.2.2**；证据：0 告警 0 错误，产物自证 `yabai-v7.2.2`，含 `view follow` 日志串
- 待办：部署实测；判据见 `domains/space-management/scenarios.md` S10（成功 = 全程至多一条 `focus … once`；你忙着操作时 = `dropped` 一行、视图不动）

**7.2.0「全屏记忆」事故 → 已回退重写（2026-10-10）**：`window_manager_remember_geometry` 对 `space_window_list()` 的池内存 `free()` → libmalloc abort 崩溃循环；修正版已去 free（2 处）+ 改用只读 `space_manager_query_view`；现场补丁 `/tmp/fullscreen-restore-7.2.0.patch`；教训见 `systemPatterns.md`

**当前焦点**：macOS 27.0.1 系统侧空间恢复问题排查（见下）

### 🐞 系统侧空间恢复问题 x2（27.0.1）

- **开机主屏无桌面**：WindowManager 日志 `managed space order: [6,6,6,6,6,6,6,6]`（主屏损坏）+ 反复 `No visible space found for display: 37D8832A-…; skipping`；`com.apple.spaces.plist` 含幽灵显示器 `F03C6F6E-…`；`space --create` 可修；daemon 开机以来 create/destroy = 0
- **全屏退出窗口回落 desktop 1**：全屏空间销毁后系统直接 `SPACE_CHANGED: 50`（= display1 index1），期间无 `window --space` 命令；yabai 侧搬移路径已穷举（命令 / 规则 / 自动指派死代码 / SA 无该 opcode）→ 系统侧行为；**绕过已实现（7.2.1）**
- **处置**：清幽灵记录 / 复位 `com.apple.spaces`（见 S9）

### 🔎 系统更新后核查（27.0.1 / 26A434，2026-09-30）

- SA 与创建路径正常（Dock 2571.0.6.402，pattern 命中不变，当天两次成功创建）
- yabai 核心操作正常；唯一错位 = yabai 的 `index` 是**全局序**，27.0.1 Mission Control 按**每显示器独立**编号 → 多显示器下 `focus N` 与"看到的 Desktop N"不一致（`domains/space-management/` §1.5 / S8）；处置：不改 yabai，绑定层用 `query --spaces --display` 取当前显示器第 N 个

### ✅ macOS 27 空间创建已修好（7.1.29，2026-09-15 端到端实测通过）

- 机制（G3′）：调用 Dock 自己的 Swift 创建 helper（pattern 0x2bb62c）`helper(cid, 0, 0, SwiftString(displayUUID), __swiftEmptyArrayStorage) → 新 spid`；完整逆向见 `docs/reverse-engineering-macos27-space-create.md`，领域结论见 `domains/scripting-addition/`、`domains/dock-reverse-engineering/`
- 最小注入取证（`/tmp/spacetest/minpay.dylib`）：`A displayUUID -> 0xcd`，spaces 9 → 10，Dock 未崩
- 两个被推翻的假设：**不是 cid 问题**（`[dockConnection]` == `SLSMainConnectionID()`）；**不是 uuid 语义**（显示器 UUID 即可，随机 UUID 属另一路径）
- 三个坑：签名状态与分支指令配对（未签名裸地址→`blr`；已签名指针 remove/move/setFrontWindow/addSpace→C 调用；dlsym→`blraaz`）；`__swiftEmptyArrayStorage` 不可 dlsym（literal pool slot `0x3c3998` 解码，取不到就不调用）；image 相对 offset 要加在 header 指向的运行时地址
- `space --destroy` 未动态验证（daemon 侧被 last-user-space 拦下，请求未到 payload）
- 清理教训：大批删代码后必须核对**数据流**（关键全局量赋值点是否还在），只验"编译 + pattern 命中"不够

### 📋 更早变更（7.1.28 macOS 27 初版支持，2026-09-15，全文见归档）

- `payload.m`：`verify_os_version()` 加 27 分支（无它则 SA 全灭）；27 路径改走 WindowManager Swift 符号；握手属性 `OSAX_ATTRIB_ADD_SPACE` 兼容三者；DPPM 指纹兜底加 `nil` 判定
- `arm64_payload.m`：各 `get_*_offset/pattern` 加 27 分支（dock_spaces 0x30000 / dppm 0x40000 / remove+move 0x180000 / fix_animation 0x220000 / set_front_window 新 pattern 命中 0x192bc；add_space 与 space_create_entry 27 无实现 → 0）
- 结果：初版 7.1.28 的 `space --create` 让 Dock 崩（PAC，见上）；7.1.29 修正
- 发布（2026-09-15）：ai-base `877e4b1` → `58edb26` → `17318fb`；dev `fbca387` / `0994274`；master `f2edcba` / `15ae877`（逐级 cherry-pick，三支已 push）

### 🧭 规则体系（2026-09-15 重写，正文见 `AGENTS.md`）

- R5/R5.5 授权机械判定（提交≠推送≠pick + 执行前自检）· R14 三级 cherry-pick + 功能/版本/记忆三段提交 · R15 五处版本号 · R12 冷归档 · R19 领域知识库（3 领域 × 五件套 + 条目元数据 + 维护触发表）

## 已知设计限制 (不处理)

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字 (1秒覆盖) | Apple 未暴露相关 API，无完美解法 |

---

## 📚 历史锚点

- macOS 26 世代（空间创建入口 `0x1f07d4`、dock_spaces 双重保险、上游同步 30 commits → 7.1.25、opacity 优化 `window_manager_enforce_rule_opacity()`）：细节已归档 `archive/activeContext-2026-10.md`，领域结论见 `domains/`


---

## 快照 2026-10-10 05:40（7.2.4 时替换掉的 activeContext 全文）

# Active Context - yabai

## Current Work Focus

**7.2.3「视图跟随」事件驱动（2026-10-10）— 编译通过，待实测**

- 目标没变：退出全屏后视图跟随窗口回到来源空间；要求**快**、**只切一次**、**不与人抢**
- 7.2.2 的问题是慢：固定等 0.5 秒安静 → 你实测"要在 desktop1 等一会"
- 7.2.3 改为**事件驱动**：退出时系统自己会先把视图切到该显示器第一个桌面（`SPACE_CHANGED: 50`，前面无任何客户端命令 = 系统行为），**这条事件本身就是"系统复位完成"的信号** → 收到即切（毫秒级）；0.8 秒定时器降级为"什么都没切"时的兜底
- 让位规则保留：外部 `space …` / `window --focus/--space/--display` 命令先到 → `view_follow_abort` → 放弃（不与你抢）
- 实现：`window_manager_view_follow_on_space_change()` 由 `SPACE_CHANGED` 处理器调用（事件循环线程内直接切）；`VIEW_FOLLOW` 事件只服务兜底定时器
- 版本：7.2.2 → **7.2.3**；证据：0 告警 0 错误
- 待办：部署实测；判据见 `domains/space-management/scenarios.md` S10

**7.2.0「全屏记忆」事故 → 已回退重写（2026-10-10）**：`window_manager_remember_geometry` 对 `space_window_list()` 的池内存 `free()` → libmalloc abort 崩溃循环；修正版已去 free（2 处）+ 改用只读 `space_manager_query_view`；现场补丁 `/tmp/fullscreen-restore-7.2.0.patch`；教训见 `systemPatterns.md`

**当前焦点**：macOS 27.0.1 系统侧空间恢复问题排查（见下）

### 🐞 系统侧空间恢复问题 x2（27.0.1）

- **开机主屏无桌面**：WindowManager 日志 `managed space order: [6,6,6,6,6,6,6,6]`（主屏损坏）+ 反复 `No visible space found for display: 37D8832A-…; skipping`；`com.apple.spaces.plist` 含幽灵显示器 `F03C6F6E-…`；`space --create` 可修；daemon 开机以来 create/destroy = 0
- **全屏退出窗口回落 desktop 1**：全屏空间销毁后系统直接 `SPACE_CHANGED: 50`（= display1 index1），期间无 `window --space` 命令；yabai 侧搬移路径已穷举（命令 / 规则 / 自动指派死代码 / SA 无该 opcode）→ 系统侧行为；**绕过已实现（7.2.1）**
- **处置**：清幽灵记录 / 复位 `com.apple.spaces`（见 S9）

### 🔎 系统更新后核查（27.0.1 / 26A434，2026-09-30）

- SA 与创建路径正常（Dock 2571.0.6.402，pattern 命中不变，当天两次成功创建）
- yabai 核心操作正常；唯一错位 = yabai 的 `index` 是**全局序**，27.0.1 Mission Control 按**每显示器独立**编号 → 多显示器下 `focus N` 与"看到的 Desktop N"不一致（`domains/space-management/` §1.5 / S8）；处置：不改 yabai，绑定层用 `query --spaces --display` 取当前显示器第 N 个

### ✅ macOS 27 空间创建已修好（7.1.29，2026-09-15 端到端实测通过）

- 机制（G3′）：调用 Dock 自己的 Swift 创建 helper（pattern 0x2bb62c）`helper(cid, 0, 0, SwiftString(displayUUID), __swiftEmptyArrayStorage) → 新 spid`；完整逆向见 `docs/reverse-engineering-macos27-space-create.md`，领域结论见 `domains/scripting-addition/`、`domains/dock-reverse-engineering/`
- 最小注入取证（`/tmp/spacetest/minpay.dylib`）：`A displayUUID -> 0xcd`，spaces 9 → 10，Dock 未崩
- 两个被推翻的假设：**不是 cid 问题**（`[dockConnection]` == `SLSMainConnectionID()`）；**不是 uuid 语义**（显示器 UUID 即可，随机 UUID 属另一路径）
- 三个坑：签名状态与分支指令配对（未签名裸地址→`blr`；已签名指针 remove/move/setFrontWindow/addSpace→C 调用；dlsym→`blraaz`）；`__swiftEmptyArrayStorage` 不可 dlsym（literal pool slot `0x3c3998` 解码，取不到就不调用）；image 相对 offset 要加在 header 指向的运行时地址
- `space --destroy` 未动态验证（daemon 侧被 last-user-space 拦下，请求未到 payload）
- 清理教训：大批删代码后必须核对**数据流**（关键全局量赋值点是否还在），只验"编译 + pattern 命中"不够

### 📋 更早变更（7.1.28 macOS 27 初版支持，2026-09-15，全文见归档）

- `payload.m`：`verify_os_version()` 加 27 分支（无它则 SA 全灭）；27 路径改走 WindowManager Swift 符号；握手属性 `OSAX_ATTRIB_ADD_SPACE` 兼容三者；DPPM 指纹兜底加 `nil` 判定
- `arm64_payload.m`：各 `get_*_offset/pattern` 加 27 分支（dock_spaces 0x30000 / dppm 0x40000 / remove+move 0x180000 / fix_animation 0x220000 / set_front_window 新 pattern 命中 0x192bc；add_space 与 space_create_entry 27 无实现 → 0）
- 结果：初版 7.1.28 的 `space --create` 让 Dock 崩（PAC，见上）；7.1.29 修正
- 发布（2026-09-15）：ai-base `877e4b1` → `58edb26` → `17318fb`；dev `fbca387` / `0994274`；master `f2edcba` / `15ae877`（逐级 cherry-pick，三支已 push）

### 🧭 规则体系（2026-09-15 重写，正文见 `AGENTS.md`）

- R5/R5.5 授权机械判定（提交≠推送≠pick + 执行前自检）· R14 三级 cherry-pick + 功能/版本/记忆三段提交 · R15 五处版本号 · R12 冷归档 · R19 领域知识库（3 领域 × 五件套 + 条目元数据 + 维护触发表）

## 已知设计限制 (不处理)

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字 (1秒覆盖) | Apple 未暴露相关 API，无完美解法 |

---

## 📚 历史锚点

- macOS 26 世代（空间创建入口 `0x1f07d4`、dock_spaces 双重保险、上游同步 30 commits → 7.1.25、opacity 优化 `window_manager_enforce_rule_opacity()`）：细节已归档 `archive/activeContext-2026-10.md`，领域结论见 `domains/`


---

## 快照 2026-10-10 05:40（7.2.5 时替换掉的 activeContext 全文）

# Active Context - yabai

## Current Work Focus

**7.2.4「视图跟随」：等系统那条变化 + 聚焦窗口（2026-10-10）— 编译通过，待实测**

- 7.2.3（收到空间变化立刻切）实测仍落 desktop1，日志给出两个原因：
  1. 我们的切换**早于**系统自己的 `SPACE_CHANGED: 50` → 被它覆盖（fallback 0.8 秒会抢在系统前面）
  2. 切完之后**前台 app 是 cmux**（该桌面上有 cmux 窗口），你的 `window_focused_event_script.sh` 随即 `space --focus 1` + `window --focus 10541` 把视图拉回 desktop1 —— 该脚本取的是**该 app 的第一个窗口**（`.[0]`），不是焦点窗口
- 7.2.4 对策：
  - fallback 0.8 → **2.0 秒**（确保不抢在系统的空间变化之前；主触发仍是"系统切到某用户空间"那条事件）
  - 切换后 150 ms **聚焦被还原的窗口**（同你脚本的两步：先 space 再 window）→ 前台 app 变成 Discord，且它的窗口就在该桌面 → 你的脚本无事可做，不会再拉走
  - 相关日志加毫秒时间戳（`t=`）便于复核时序
- 版本：7.2.3 → **7.2.4**；证据：0 告警 0 错误
- 待办：部署实测；若仍被拉走，下一手是改脚本 `.[0]` → 焦点窗口（需你同意，属你的配置）

**7.2.0「全屏记忆」事故 → 已回退重写（2026-10-10）**：`window_manager_remember_geometry` 对 `space_window_list()` 的池内存 `free()` → libmalloc abort 崩溃循环；修正版已去 free（2 处）+ 改用只读 `space_manager_query_view`；现场补丁 `/tmp/fullscreen-restore-7.2.0.patch`；教训见 `systemPatterns.md`

**当前焦点**：macOS 27.0.1 系统侧空间恢复问题排查（见下）

### 🐞 系统侧空间恢复问题 x2（27.0.1）

- **开机主屏无桌面**：WindowManager 日志 `managed space order: [6,6,6,6,6,6,6,6]`（主屏损坏）+ 反复 `No visible space found for display: 37D8832A-…; skipping`；`com.apple.spaces.plist` 含幽灵显示器 `F03C6F6E-…`；`space --create` 可修；daemon 开机以来 create/destroy = 0
- **全屏退出窗口回落 desktop 1**：全屏空间销毁后系统直接 `SPACE_CHANGED: 50`（= display1 index1），期间无 `window --space` 命令；yabai 侧搬移路径已穷举（命令 / 规则 / 自动指派死代码 / SA 无该 opcode）→ 系统侧行为；**绕过已实现（7.2.1）**
- **处置**：清幽灵记录 / 复位 `com.apple.spaces`（见 S9）

### 🔎 系统更新后核查（27.0.1 / 26A434，2026-09-30）

- SA 与创建路径正常（Dock 2571.0.6.402，pattern 命中不变，当天两次成功创建）
- yabai 核心操作正常；唯一错位 = yabai 的 `index` 是**全局序**，27.0.1 Mission Control 按**每显示器独立**编号 → 多显示器下 `focus N` 与"看到的 Desktop N"不一致（`domains/space-management/` §1.5 / S8）；处置：不改 yabai，绑定层用 `query --spaces --display` 取当前显示器第 N 个

### ✅ macOS 27 空间创建已修好（7.1.29，2026-09-15 端到端实测通过）

- 机制（G3′）：调用 Dock 自己的 Swift 创建 helper（pattern 0x2bb62c）`helper(cid, 0, 0, SwiftString(displayUUID), __swiftEmptyArrayStorage) → 新 spid`；完整逆向见 `docs/reverse-engineering-macos27-space-create.md`，领域结论见 `domains/scripting-addition/`、`domains/dock-reverse-engineering/`
- 最小注入取证（`/tmp/spacetest/minpay.dylib`）：`A displayUUID -> 0xcd`，spaces 9 → 10，Dock 未崩
- 两个被推翻的假设：**不是 cid 问题**（`[dockConnection]` == `SLSMainConnectionID()`）；**不是 uuid 语义**（显示器 UUID 即可，随机 UUID 属另一路径）
- 三个坑：签名状态与分支指令配对（未签名裸地址→`blr`；已签名指针 remove/move/setFrontWindow/addSpace→C 调用；dlsym→`blraaz`）；`__swiftEmptyArrayStorage` 不可 dlsym（literal pool slot `0x3c3998` 解码，取不到就不调用）；image 相对 offset 要加在 header 指向的运行时地址
- `space --destroy` 未动态验证（daemon 侧被 last-user-space 拦下，请求未到 payload）
- 清理教训：大批删代码后必须核对**数据流**（关键全局量赋值点是否还在），只验"编译 + pattern 命中"不够

### 📋 更早变更（7.1.28 macOS 27 初版支持，2026-09-15，全文见归档）

- `payload.m`：`verify_os_version()` 加 27 分支（无它则 SA 全灭）；27 路径改走 WindowManager Swift 符号；握手属性 `OSAX_ATTRIB_ADD_SPACE` 兼容三者；DPPM 指纹兜底加 `nil` 判定
- `arm64_payload.m`：各 `get_*_offset/pattern` 加 27 分支（dock_spaces 0x30000 / dppm 0x40000 / remove+move 0x180000 / fix_animation 0x220000 / set_front_window 新 pattern 命中 0x192bc；add_space 与 space_create_entry 27 无实现 → 0）
- 结果：初版 7.1.28 的 `space --create` 让 Dock 崩（PAC，见上）；7.1.29 修正
- 发布（2026-09-15）：ai-base `877e4b1` → `58edb26` → `17318fb`；dev `fbca387` / `0994274`；master `f2edcba` / `15ae877`（逐级 cherry-pick，三支已 push）

### 🧭 规则体系（2026-09-15 重写，正文见 `AGENTS.md`）

- R5/R5.5 授权机械判定（提交≠推送≠pick + 执行前自检）· R14 三级 cherry-pick + 功能/版本/记忆三段提交 · R15 五处版本号 · R12 冷归档 · R19 领域知识库（3 领域 × 五件套 + 条目元数据 + 维护触发表）

## 已知设计限制 (不处理)

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字 (1秒覆盖) | Apple 未暴露相关 API，无完美解法 |

---

## 📚 历史锚点

- macOS 26 世代（空间创建入口 `0x1f07d4`、dock_spaces 双重保险、上游同步 30 commits → 7.1.25、opacity 优化 `window_manager_enforce_rule_opacity()`）：细节已归档 `archive/activeContext-2026-10.md`，领域结论见 `domains/`

---

> **更正（2026-10-23，7.2.6）**：上文“不是 uuid 语义（显示器 UUID 即可，随机 UUID 属另一路径）”的结论**错误**。`CGSSpaceCreate` 的 `uuid` 参数是**新空间身份**；传显示器 UUID 会让同显示器所有空间共享身份，导致 `com.apple.spaces` 开机恢复塌缩、主屏丢壁纸。证据与修复见 `domains/scripting-addition/practices.md`、`domains/space-management/principles.md` 与 `docs/reverse-engineering-macos27-space-create.md` §6.5。
