# Active Context - yabai

## 当前工作焦点（2026-11-01）

- 未提交代码审查已完成双轴检查；审查发现已按“C `window --fast-focus` 为唯一落位实现”修复，未提交。
- `src/message.c`：输入门改为 `kCGAnyInputEventType` 时间戳（覆盖键盘/鼠标/滚轮/手势）；目标窗口优先 `application_focused_window`，再回退首个标准窗口。
- `tests/src/fast_focus.c`：新增 gate 与 focused-first 测试；`make -C tests all` 6/6 通过；`make` 0 warning。
- 当前运行 daemon 仍是旧 7.2.40；真实 Cmd+Tab 8 次样本（cmux↔IntelliJ）`latency_ms` 301–357ms、`focus_ms` 39–93ms、无失败。C 新路径需用户 `make deploy` 后验证。
- **7.2.41**：`fast_window_switch off` 的 Dock 重启等待移到 detached thread，修复事件循环 `wait4` 卡死；off 会恢复 `workspaces-auto-swoosh=true`，Dock 重启后原生 Cmd+Tab 应恢复。构建 0 warning，tests 6/6；运行时待部署。
- 剩余延迟主要来自 signal 前 App 激活；脚本/C 落位无法稳定低于 200ms。预激活接管 Cmd+Tab 是独立大功能，当前不做。

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
