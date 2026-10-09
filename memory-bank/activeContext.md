# Active Context - yabai

## Current Work Focus

**7.2.5「视图跟随」：只聚焦窗口，不抢着切桌面（2026-10-10）— 编译通过，待实测**

- 7.2.4 实测（带毫秒时间戳）：我们的切桌面动作**抢在了你的 front-switch 脚本的判断窗口里**——脚本在切换动画中重新判断"前台 app 的窗口不在这"，又把视图拉回去，于是来回跳、并有概率停在 desktop1
- 7.2.5 改为：
  - **不再由 yabai 切桌面**；只把被还原的窗口提到前台（`view_follow_on_space_change()` → `view_follow_focus_window()`，0.15 秒后再聚焦）
  - 前台 app 变成 Discord 且它的窗口就在目标桌面 → 你的脚本（即时路径）自己把视图带过去；yabai 不再与它抢
  - 只有当**没有任何人**切视图时，yabai 才在 **0.4 秒**（原 2 秒）后补切一次（`view_follow_fire()`：`space_is_visible` / `abort` 判定不变）
- 脚本侧回滚：去掉上一版加的 `sleep 0.15` 与"可见空间 1 秒内变过就跳过"（实测造成**卡顿感**与**漏跳**）；保留"整 app 可见性"与 `has-focus` 优先
- 版本：7.2.4 → **7.2.5**；证据：0 告警 0 错误；脚本用影子 yabai 验证（16 ms 无动作 / 133 ms 执行，含原有 0.1 秒）
- 待办：部署实测（判据：全程最多一次可见切换；`focus window=15973` 后紧跟你的脚本一次跳转）

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
