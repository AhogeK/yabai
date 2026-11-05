# Active Context - yabai

## 当前工作焦点（2026-11-06）

- **7.2.42：普通 Cmd+Tab 回归已修复，fast landing 回到脚本实现**。C 版 `--fast-focus-window` 只认 signal wid / AX 焦点窗口；`application_front_switched` 在 AX 解析失败时不发 `window_focused`；叠加 `fast_window_switch on` 关掉 auto-swoosh → 没有任何路径切 desktop。源码逻辑回 7.2.41，版本 bump 到 7.2.42。
- **当前实现**：`examples/app_fast_land.sh` 与 `~/.config/yabai/app_fast_land.sh`（同一文件，逐字节一致）；`application_front_switched`（pid）+ `window_focused`（wid）双 signal；目标解析 wid → pid → has-focus → first standard → first window。
- **判定顺序**：最小化 → deminimize + 落位；可见且同 display → `skip-visible`；可见但异 display → `display --focus`（对已聚焦窗口同样执行）；隐藏 → `window --focus`。
- **早退已移除（2026-11-06 实验）**：曾用“已聚焦且可见”提前退出省一次查询；实测切换显示器后约 0.4s 内 daemon 仍把旧显示器窗口报为焦点（6 次采样 1 次不一致，稳定态 6/6 一致），会吞掉 display 跟随，故删除该分支，代价约 +13ms。
- **争抢处理**：单飞锁 30×20ms=600ms 上限并写 owner pid；日志超 256KB 保留最后 200 行（每次调用检查，覆盖 skip 路径）；每次调用只读一次时钟。
- **测试**：`tests/script/fast_land_test.sh`（stub `yabai`）21/21，覆盖禁用、可见 no-op、隐藏、最小化、跨 display、已聚焦但在其他显示器、pid 解析、锁占用、日志轮转；`make` 0 warning；`make -C tests all` 6/6。
- **开销实测**：重复事件 wid 40ms、pid 48ms（原 94/60ms）；落位 130–140ms。
- **待验证**：真实 Cmd+Tab 与真实同 App IDEA 点击（需用户按键），状态只能标“待验证”。
- **7.2.42 已发布**：ai-base `0d8cce3`（功能）/ `b4da019`（文档）/ `81af1ca`（版本）/ `ea8b2b5`（AI）；dev `117f66d` / `6a29a57` / `9c960da` / `7cca140`；master `c4c1cbe` / `ec6482b` / `f08520e` / `26d5019`；三支已推送且与 origin 一致。
- **顺带修复**：`7.2.21` 的 CHANGELOG 条目从未进入 dev/master（只有 ai-base 的 `9088d9c` 带过），已用 `7cca140` / `26d5019` 补齐，现三支 CHANGELOG 完全一致。
- **版本**：源码 7.2.42；机器上已装的二进制同为 7.2.42，但由已回退的 C 改动构建，需 `make deploy` 换成当前源码。
- 剩余延迟主要来自 signal 前 App 激活（144–316ms）；只有预激活接管 Cmd+Tab 才可能低于 200ms，属独立功能。

## macOS 27.2 支持（7.2.7–7.2.13，已验证）

- 27.2 Dock `2571.1.32.402`；旧扫描越过 `__TEXT` 进入保护页导致 Dock 崩溃循环，恢复为停 yabai → 移 osax → kickstart Dock → 重启。
- 安全护栏：扫描钳制到 `__TEXT` 尾部；未知 Dock 构建 fail-closed；27.x 构建白名单。
- 27.2 profile：create helper `0x20ce00`，Spaces 单例槽 `0x329be0`，空数组单例 `0x2ef0d8`；create/focus/destroy/move/排序均真机验证。
- 空间编号恢复全局编号；skhdrc 已回滚为直接 N。

## 焦点与 Space 切换（7.2.14–7.2.40）

- `window --focus` 已包含目标 space 不可见时的 `space_manager_focus_space` + `space_manager_wait_until_visible` + `window_manager_focus_window_with_raise`；不要再先调 `space --focus`，否则动画竞态。
- 7.2.18：`skip_window_focus_animation` 默认 off；auto-swoosh=false 与 skip-off 配套，避免两个切换互相点火。
- 7.2.23–7.2.40：反复修复 fast landing 回弹、目标窗口、显示器和输入门。最新修正是 C fast-focus 的任意 HID 输入门 + focused-first 选择；运行时尚未部署。
- 当前 8 次真实样本证明多窗口 IntelliJ 落到 `AXFocusedWindow=15149`，不再落错窗口；单次总延迟约 300–360ms。

## 空间身份修复（7.2.6，已验证）

- 27 create 曾把显示器 UUID 当空间身份，`com.apple.spaces` 持久化重复身份，开机丢桌面。
- 修复：create 使用 `CFUUIDCreate` 新身份并校验落点；清理域后需确认空壳再重启；修复后三屏 order `[1]/[6]/[7]`，壁纸恢复。

## Dock 动画调查

- Dock 参数层未证明可关闭 Cmd+Tab 的 WindowServer 过渡；`SLSTransactionSetManagedDisplayIsAnimating` 改 0 后动画仍在。
- 2026-10-29 18:48 直接 root LLDB attach WindowServer 导致 SIGSTOP/GUI 冻结；**禁止再次 attach**，只能非停止采样或带 watchdog 短时 attach。
- 结论：保留系统过渡；不要在 signal 后继续追动画。

## 历史锚点

- 全屏还原 workaround 已在 7.2.22 退役；macOS 已修复。
- macOS 27 空间创建完整历程：`docs/plans/2026-10-28-macos-27.2-support.md`、`domains/space-management/`。
- 7.2.0–7.2.22 详细时间线：`memory-bank/archive/activeContext-2026-10.md`（如缺，查 progress 历史摘要）。
- 7.2.23–7.2.40 细节：`progress.md` 当前阶段摘要。

## 已知限制（暂不处理）

| 问题 | 原因 |
|---|---|
| 跨 space 失焦窗口透明度不恢复 | 原版设计 |
| 10 次重试魔法数字 | Apple 未暴露相关 API |
| Dock 底部 53px 间隙 | 无稳定重现，暂缓 |
| 总切换延迟 <200ms | 需预激活接管 Cmd+Tab，属独立功能 |

## Memory Bank 状态

| 文件 | 目标 |
|---|---|
| activeContext.md | ≤150 行 |
| progress.md | ≤100 行 |
| systemPatterns/techContext | 保持 ≤80 行 |
| 领域文件 | 每领域五件套，≤200 行 |
