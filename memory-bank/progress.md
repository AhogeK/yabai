# Progress - yabai

## Current Phase: 7.2.21 deploy default ✅ 源码完成，待提交 (2026-10-30)

---

## Phase History

### Phase 46: Dock 平移动画：Dock 参数层已排除，WindowServer 待证 🔬 (2026-10-29)
- 实测否定：launch closure `x1=0`、Cmd+Tab `0x1268dc x1=0`、`x2=1`、`isAnimating=false`
- 追加 A/B：Dock 点击 magpie(space2)->cmux(space1)，30fps；`0x1000c4878` 的 `isAnimating=1 -> 0` readback 确认，动画仍存在；该 flag 未证明是开关，断点命中未完成
- 结论：此前“yabai 绝对做不到”撤回；Dock 参数层无解决证据，WindowServer/WindowManager transition 未定位；需 root attach 或更多静态取证
- 源码回退 7.2.18 / OSAX 2.1.41（编译验证），未安装；计划 `docs/plans/2026-10-29-dock-space-transition-animation.md`（closed；7.2.19 运行时已验证，7.2.20 source 待运行时验证）
- 2026-10-29 18:48 事故：直接 root LLDB attach WindowServer → WindowServer 停止、GUI 冻结、系统自动重启；无持久修改；root attach 方案废弃
- 2026-10-29 18:53 基线恢复：安装 7.2.18 / OSAX 2.1.41，源码 diff 空，系统与 space 查询正常
- 2026-10-29 native fast landing v2（已部署）：窗口可见性驱动，直接 focus space + focus window；编译通过 7.2.18
- 2026-10-29 v2 实测：fast front switch result=0、SPACE_CHANGED 正常，但 WindowServer 滑动仍存在；ReduceMotionEnabled=1 也无效；决策：保留 fast landing，接受滑动
- 2026-10-29 7.2.20 复审修复：fast landing 移到窗口解析后；移除 pending 拦截；effective sticky helper；分离 skip/fast 文档；tests 4/4；构建 0 warning；ai-base 87d35c7/d96ed38/3089347/a710a3c，dev fa4893a/4741e79/95c2f88，master 2d10a3f/32bbbdf/5e7d2db；2026-10-30 7.2.21 deploy：make deploy 写 auto-swoosh=0 并重启 Dock；ai-base 928c024/9088d9c，AI 专属，不 cherry-pick；AI 记录本次提交推送；dev/master 有旧 target，无 7.2.21 改动

### Phase 45: REA/Ghidra provider + reverse-engineering skill v3 ✅ (2026-10-29)
- `reverse-engineering` SKILL v3：任何 rea 调用前强制加载 `reverse-engineer-anything`；明确 REA 技能 + 当前 `tools/list` 优先
- Ghidra 12.1.4 独立安装（REA 6.8.0 唯一验证版）；Homebrew 12.2 不可指向；`~/.zprofile` + mcp.json 同步，doctor healthy
- 新增 §1a：用前/每月版本复核；新版支持新 Ghidra 时 side-by-side 安装并重启
- 验证：baseline 子代理误答 Homebrew 路径且无升级流程；GREEN 子代理正确选 12.1.4、先读 REA 技能、给出 side-by-side 升级

### Phase 44: 27.2 焦点切换（7.2.18）✅ 用户验证 (2026-10-29)
- 根因：27 动画来自 `workspaces-auto-swoosh` 窗口排序跟随（Dock 日志 `ordered on non-visible space`）
- 7.2.15：27 IOHID payload + companion；7.2.17：等待 display 稳定、目标 space 可见后才聚焦，超时中止
- 7.2.18：skip 默认 off；最终配置 auto-swoosh=false + skip off，用户验证无问题
- 发布：ai-base 功能 `c9c1ff2` / 版本 `5fdb079`；dev `cff32ad`/`f11c765`；master `1cce764`/`ffb5952`

### Phase 43: window focus fast landing（7.2.14）✅ 已包含在 7.2.18 (2026-10-29)
- 事实：`window --focus` 只做 SLPS/AX 聚焦；27.2 对窗口激活引发的隐式 space 切换播放横移动画，与脚本无关
- 修复：目标 space 不可见且窗口未最小化时，命令内部先 `space_manager_focus_space(sid)`（SA/SLS 直切），再 SLPS 聚焦；失败回退原生
- 提交：ai-base 功能 `9e7bcb8` / 版本 `04d4d8c`；dev `b0c71a8`/`24c3376`；master `27ca10e`/`d1aa085`
- 验证：随 7.2.18 用户验证通过；直接 space focus 录屏无横移
- 文档：`docs/plans/2026-10-29-window-focus-fast-landing.md`（completed）

### Phase 42: macOS 27.2 支持（崩溃修复 + 全功能适配）✅ (2026-10-28)
- 根因：固定扫描窗口越过新 Dock 的 `__TEXT` 末尾，读进保护页；Dock 启动即崩（崩溃循环）
- 恢复/修复：移除 SA + 重启（`launchctl` 服务名 `com.apple.Dock.agent`）；`hex_find_seq` 钳制到段末尾；`verify_dock_build()` 未知 Dock 构建拒绝初始化（7.2.7 / OSAX 2.1.35）
- 27.2 适配：7.2.8 create/focus、7.2.9 destroy（CGSSpaceDestroy）、7.2.10 move/排序（CGSMoveManagedSpaceToDisplayIndex + SLSTransaction*）、7.2.11 修复 profile 跳过的 Swift 桥解析、7.2.13 修复 __DATA_CONST 段校验误判并**运行验证 create/focus/move/排序/destroy 全部通过**；7.2.12 上线前审计 + 双轴代码审查（段范围校验、fail-closed、握手属性、落点/焦点、autoreleasepool、文档）；桌面编号恢复全局（skhdrc 已回滚）；跨 space window focus 不影响（daemon 走 _SLPS+AX）
- 发布：ai-base `5a53ab8` · dev `ff62fb3` · master `ac1aaa4`；三支已推送，代码内容一致，dev/master 无 AI 文件

### Phase 41: 空间身份修复 —— 主屏失背景根因 ✅ (2026-10-23)
- 根因/机制：`space --create` 把显示器 UUID 当新空间身份（系统 “+” 每次新 UUID）；相同身份在 `com.apple.spaces` 重复 → 开机恢复全部塌缩到同一 id → 只见 1 个桌面、无壁纸
- 修复：`src/osax/payload.m` create 传 `CFUUIDCreate` 新 UUID + 落点显示器校验；版本 7.2.5→7.2.6，OSAX 2.1.33→2.1.34
- 状态：编译 0 警告；已部署实测（新空间 uuid 唯一）+ 清理旧模型后重启验证通过（15:52，order [1]/[6]/[7]）

### Phase 40: 原生全屏还原 —— 送窗口 + 视图跟随 ✅ (2026-10-10)
- 背景：27.0.1 全屏退出后窗口与视图都落到该显示器第一个桌面（`domains/space-management/scenarios.md` S10）
- 7.2.0：进全屏记来源空间（+分屏侧），全屏空间销毁后送回；含一次崩溃事故——对 `space_window_list()` 池内存 `free()` → libmalloc abort，已移除 free（2 处）
- 7.2.1：视图跟随第一版（重试抢回）→ **实测否掉**：日志显示每次切回第一个桌面都是外部 `space --focus` 命令，重试与它互相放大成反复闪回
- 7.2.2：只切一次——登记意图 + 等 0.5 秒安静 + 外部空间/窗口命令立即放弃（实测可用但**太慢**：要在 desktop1 等一会）
- 7.2.3：改**事件驱动**（系统那条 `SPACE_CHANGED` 即"复位完成"信号）→ 实测仍落 desktop1：我们的切换早于系统的空间变化被覆盖，且切完后前台 app 是 cmux，用户的 front-switch 脚本（取 app 的**第一个窗口**）把视图拉回 desktop1
- 7.2.4 实测暴露循环：我们的切换 → yabai 为被切到前台的 cmux 再发一次 front-switch → 用户的 `window_focused_event_script.sh` 把视图拉回 desktop1（其 `.[0]` 语义 + 空间动画误判）；已修脚本：等动画落定 + 「可见空间 1 秒内刚变过就跳过」+ 整 app 可见性判断（用户授权，备份 `.bak`）
- 7.2.4：兜底 0.8 → **2 秒**（不抢在系统前面）+ 切换后 150 ms **聚焦被还原的窗口**（前台 app 变成 Discord 且窗口在同桌面，外部脚本无事可做）+ 日志加毫秒时间戳
- 7.2.5：不再由 yabai 切桌面（抢切会插进用户 front-switch 脚本的判断窗口 → 来回跳）；只聚焦被还原窗口，视图交给脚本即时路径，只有没人切时 0.4 秒后兜底补切。脚本侧回滚掉 `sleep 0.15` + "空间刚变就跳过"（实测卡顿 + 漏跳）
- 版本：7.2.0 → 7.2.1 → 7.2.2 → 7.2.3 → 7.2.4 → **7.2.5**（OSAX_VERSION 不变）；编译 0 告警 0 错误
- 分支同步：补齐 dev/master 缺失的 `#2780 implement` 与 `#2217`（内容回到与 ai-base 一致），普通推送 dev `83c7916` / master `70e084b`
- 状态：✅ 已实测通过（退出全屏效果 OK、无新崩溃）+ 已提交推送（ai-base 6115f7b / dev 4e39363 / master 6c8152e，7.2.5）

> Phase 39（macOS 27 SA 修复）已归档至 `archive/progress-2026-09.md`。

### Phase 38: macOS 26.6 (25G72) space creation fix ✅ (2026-08-05)
- space_create_entry 0x1f07d8 → 0x1f07d4；dock_spaces pattern 0 匹配 → DOUBLE-ANCHOR 兜底（0x488028）
- DPPM 0x4880d0 不受影响；OSAX_VERSION 2.1.29 → 2.1.30 → 2.1.31

### Phase 37: 上游 #2799 add_space pattern (2026-06-15) ✅
- macOS 26.6 Apple Silicon add_space pattern 通配化（48 89 FC 97 → ?? ?? ?? 97）

### Phase 36: 上游 #2788 同步 (2026-05-10) ✅
- 版本 7.1.26；`SLSPerformAsynchronousBridgedWindowManagementOperation`（SIP enabled 下跨 space 移动窗口）

### Phase 35: 上游 30 commits 全量同步 (2026-04-26) ✅
- `7c4c5ba` → `f51e4b5`，版本 7.1.21 → 7.1.25，报告见 `docs/upstream-sync-report-2026-04-26.md`

### Phase 1-34: macOS 26 Tahoe 空间创建从 0 到 1 ✅
- 30~33: Space 创建成功（Swift 调用约定 + 原子 asm 宏 + DPPM 动态定位 + 多显示器）
- 25~29: 地址重复计算修复 / 调试代码清理
- 早期: addSpace 调用约定、自定义 asm 宏、逆向文档体系建立

---

## Key Findings（跨版本）

- macOS 26 起 Dock 用 Swift 重写（DockCore 框架）；macOS 27 起空间/窗口管理下沉到 WindowManager.framework
- Swift 调用约定：实例方法 `self` 在 callee-saved `x20`；throwing 方法错误在 `x21`；String 是 2 word（x0/x1）
- 全局单例都在 `__DATA,__common`：可通过 "objc stub → selector → 接收者全局" 的寄存器级抽象解释做语义画像
- IOKit 在 Dock 沙箱下静默失败 → 用 CoreGraphics UUID API

## Memory Bank 状态

| 文件 | 行数 | 限制 | 状态 |
|------|------|------|------|
| activeContext.md | 95 | 150 | ✅ |
| progress.md | 100 | 100 | ✅ |
| systemPatterns.md | 63 | 80 | ✅ |
| techContext.md | 73 | 80 | ✅ |
| projectbrief.md | 22 | 50 | ✅ |
