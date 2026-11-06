# scenarios — 触发场景 → 判断 → 动作

> **系统基线**：macOS 27.2 (26B123) · Dock 2571.1.32.402 · WindowManager 462.1.41.404
> **最后验证**：2026-10-30 · **状态**：已验证（S1/S8/S11 + 27.2 全功能实测）；S10 已退役；7.2.20 fast landing 为源码/单测结论，**运行时待验证**
> **来源**：S1 排查顺序与 27.2 行为实测；S4（ivar 改名）与 S6 为推论，待实测

## S1. `yabai -m space --create` 无效果

**判断顺序（从外到内）**：

1. daemon 侧前置门：`mission_control_is_active()`、显示器是否动画中（`SPACE_OP_ERROR_*` 会直接返回）
2. SA 是否可用：`dock_spaces` 是否解析成功、`OSAX_ATTRIB_ADD_SPACE` 是否上报
3. 当前系统属哪一代（`principles.md` §1）：
   - G2（26.x）→ 入口偏移是否命中 `setFrontWindow` 式的 `pacibsp` 校验
   - G3（27+）→ `[yabai-sa][WM]` 日志：符号是否解析、`shared` 是否非空、调用返回的 `spid` 与 `error`
4. 成功后校验不变量（§3）：新 spid 是否出现在 `spacesForDisplay:`

## S2. 创建成功但壁纸/缩略图不对

**动作**：确认 DPPM 路径是否执行（`principles.md` §6）；检查传给 DPPM 的 display UUID 与创建时是否同一个。

## S3. 多显示器：空间创到了错误的显示器

**动作**：检查 `SLSCopyManagedDisplayForSpace(sid)` 是否取到目标显示器 UUID；G3 路径下 UUID 字符串必须真实传入（不得传 nil 让它走默认显示器）；必要时用 `CGDirectDisplayID` 反查确认映射。

## S4. `space --focus` 后菜单栏/缩略图与实际不一致

**动作**：属 Dock 模型未同步（`principles.md` §4）。先确认 ivar 名在当前系统是否仍为 `_displaySpaces` / `_currentSpace` `[推论]`（`object_getInstanceVariable` 返回 nil 即已改名）；改名时用新的模型入口（如 `[spaces …]` 方法）替代，而不是放弃回写。

## S5. 系统升级后只有一个空间能力坏，其他正常

**判断**：能力分属不同代际/不同入口（如 27 的创建走框架、销毁与移动仍走 Dock 内函数），因此**逐个能力独立验证**，不要因为创建坏了就认为整块失效。

## S6. `space --move` 跨显示器后壁纸丢失

**动作**：确认 `moveSpace:toDisplay:displayUUID:` 被调用（DPPM 需重新绑定），并核对 `CGSMoveManagedSpaceToDisplayIndex` 的 display index 语义 `[推论]`（index 不是 display UUID）。

## S8. 按编号操作桌面时打到了别的显示器（历史：macOS 27.0.1；27.2 已恢复全局编号）

**判断**：多显示器 + 按数字选择器（`space --focus N` / `window --space N`），发现生效的是另一台显示器上的桌面。

**27.0.1 历史**：Mission Control 曾按每显示器独立编号，需要用 `yabai -m query --spaces --display | jq -r '.[N-1].index'` 取当前显示器的 index。

**现状（27.2 / 26B123，2026-10-28 用户实测）**：Mission Control 恢复**全局编号**（三台显示器连续 Desktop 1/2/3），直接 `space --focus N` 即对应看到的 Desktop N。绑定层已回滚为直接使用 N（`~/.config/skhd/skhdrc`，备份 `skhdrc.bak-20261028-global-index`）。

## S9. 开机后主屏没有桌面 / Mission Control 连 Spaces Bar 与 `+` 都没有（macOS 27.0.1）

**判断**：这是 **macOS 侧**问题，不是 yabai。取证看登录阶段的 WindowManager 日志：

```bash
log show --last boot --predicate 'process == "WindowManager"' --style compact \
  | grep -E "managed space order|No visible space"
```

典型证据（2026-09-30 14:30 实测）：

```
WSSpaceManager: display 37D8832A-…(主屏) managed space order: [6, 6, 6, 6, 6, 6, 6, 6]   ← 损坏
E [com.apple.windowmanagement:login] No visible space found for display: 37D8832A-…; skipping（反复）
```

**动作**：
1. 立刻恢复：`yabai -m space --create`（SA 直调 CGS 建空间，会把系统存储里的该显示器条目重写成正常值）。
2. 复查存储是否脏：`plutil -p ~/Library/Preferences/com.apple.spaces.plist` —— 若出现**系统中不存在的显示器 UUID**（幽灵记录）或某显示器 `Spaces` 为空/重复，即为脏数据。
3. 预防：备份后清掉幽灵记录或整体复位该域（`defaults delete com.apple.spaces` + `killall cfprefsd`），**重启**让系统重建默认布局；重启前不要指望 yabai 常驻修复。
4. 判定责任：yabai 的 yabairc 只要没有开机动空间的 signal/脚本，就不可能是原因；SA 的 create 只是修复手段。

**更正（2026-10-23，7.2.6）**：第 4 条**不成立**。决定性对照实测——系统 Mission Control “+” 建的空间 id 33 → `uuid=442D311F…`（唯一）；yabai 建的空间 id 26 → `uuid=37D8832A…`（显示器 UUID）。即每次 `space --create` 都在写入同一身份的空间；`com.apple.spaces` 按身份持久化，开机恢复时重复身份全部映射到同一空间（`[6,6,…]`），桌面层取不到壁纸。因此“第 1 条 `space --create` 立刻恢复”只是临时遮盖并**加重污染**；正解是 create 传新 UUID（7.2.6）。

**验证（2026-10-23 15:52）**：`defaults delete com.apple.spaces` + `killall cfprefsd` + 注销/重启后，模型重建为每显示器 1 个空间（`order [1] / [6] / [7]`，`query --spaces` count=unique=3），壁纸恢复。删除后 plist 变成 42 字节空壳（`{}`）属正常，不是删除失败。

## S10. 原生全屏退出后窗口跑到该显示器第一个桌面（已退役）

> macOS 更新后系统已修复该行为；yabai 7.2.22 已删除 `fullscreen_restore` 与
> `view_follow` workaround。保留此标题仅供历史检索。

## S10.1 Front-switch script contract（独立于已退役 workaround）

- `~/.config/yabai/window_focused_event_script.sh` 仍按“整个 app 是否有可见窗口”判断，目标窗口取 `.[0]`，一次 `jq` 查询。
- 动作顺序保持 `space --focus` → `sleep 0.1` → `window --focus`；`sleep 0.1` 是等切换过渡，不能删除或改成“空间刚变就跳过”。
- 实测手感约 130–132 ms；不要加 `sleep 0.15`，也不要拆成两次 `jq`，两者分别造成卡顿/漏跳和额外延迟。

## S11. 焦点切换出现桌面横移动画（macOS 27.2，所有焦点来源）

**判断**：Dock 图标、Cmd-Tab、`window --focus`、以及纯 macOS “switch to a Space with open windows” 都通过系统激活窗口触发隐式 space 切换；27.2 对该切换播放横移动画。脚本与 `application_front_switched` 信号无关。

**动作**：
1. 27.2 上关闭 Dock 窗口排序跟随：`defaults write com.apple.dock workspaces-auto-swoosh -bool false`（需重启 Dock；同时关闭 Dock 图标跟随，由 yabai/前台脚本接管）；
2. `skip_window_focus_animation` 只管 `WINDOW_FOCUSED` 的合成手势路径，默认 off；它不控制 application front-switch 的 fast landing；
3. 7.2.19+ `fast_window_switch` 默认 on：application front-switch 先解析待刷新窗口，优先应用当前焦点窗口，排除 minimized fallback，sticky 按可见处理；目标 space 不可见时最多等 500ms 再聚焦；不因 AX pending 焦点跳过落点；
4. 有 SA 时 fast landing 走直接 SLS focus；没有 SA 时 `space_manager_focus_space` 回退合成手势，因此 Dock follow 必须保持 0；
5. 7.2.18 在 27 上等待 display 稳定后才切；`window --focus` 等目标 space 可见后才聚焦，超时中止，避免黑屏/切错；
6. 直接 `space --focus` 已确认无横移；若仍动画，检查 yabairc 是否覆盖设置或 Dock 是否已重启。

> 7.2.20：S11 的 fast landing 行为由源码与单测核对，尚未在 7.2.20 运行环境验证。

## S12. `display --focus` 后焦点归属滞后约 0.4s（macOS 27.2，已验证）

**判断**：`yabai -m display --focus <index>` 生效后，活动显示器立即切换，但 `query --windows --window` 报告的焦点窗口可能仍在旧显示器上，最长约 0.4s 才追上。稳定后焦点窗口的 display 与 `query --displays` 的 `has-focus` 一致。

**动作**：
1. 任何“窗口已聚焦就跳过 display 跟随”的早退都不安全：滞后窗口会被误判为“焦点在活动显示器”，从而吞掉 `display --focus`；
2. 判断要不要跟随显示器时，直接查 `query --displays` 的 `has-focus`，不要用窗口的 `has-focus` 推断活动显示器；
3. 复现：`display --focus A` → `display --focus B` → 立即读 `query --windows --window` 可看到旧值，`sleep 0.4` 后一致。

**验证（2026-11-06）**：3 轮 × 2 个显示器共 6 次采样，稳定态 6/6 一致；立即读取 1/6 不一致（约 0.4s 内）。

## S13. 落位后同一 App 重新上报另一窗口，形成来回落焦（macOS 27.2，已验证）

**判断**：`window --focus` 落位并切换 Space 后，App 会把“它仍视为 key window”的另一个窗口重新上报，yabai 据此再发一次 `window_focused`。若脚本按事件落位，就切回那个窗口，App 再上报——闭环。实测 IntelliJ 两个窗口分处两个 Space 时约 4 次落位/秒。

**动作**：
1. `window_focused` 落位必须按“同一 App、不同窗口、刚发生落位”过滤；实测 1 秒窗口足够覆盖闭环周期（约 250ms）；
2. 只过滤 `window_focused`，不要过滤 `application_front_switched`——后者是快速 Cmd+Tab 的来源；
3. 判别依据是事件里的 `$YABAI_WINDOW_ID` 与落位记录中的 pid/wid，不是“窗口是否可见”（闭环中目标始终处于不可见态，可见性判断拦不住）；
4. 排障时先看脚本日志的 `src=wid|pid`：闭环全部是 `src=wid`。

**验证（2026-11-06）**：受控复现 17 行/2 秒（`35530` ↔ `35832`，pid 61040）；加过滤后同类事件只产生 1 行 `skip-app-reassert`，3 秒静置无新增。
