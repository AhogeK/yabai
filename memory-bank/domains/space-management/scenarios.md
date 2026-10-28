# scenarios — 触发场景 → 判断 → 动作

> **系统基线**：macOS 27.2 (26B123) · Dock 2571.1.32.402 · WindowManager 462.1.41.404
> **最后验证**：2026-10-28 · **状态**：已验证（S1/S8/S10 + 27.2 全功能实测）
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

## S10. 原生全屏退出后窗口跑到该显示器第一个桌面（27.0.1 实测，系统侧）

**现象**：某显示器有多个桌面，窗口在 desktop 2/3，进入原生全屏（如视频通话）后退出 → **窗口与该显示器一起回到 desktop 1**。

**取证方法**（daemon 日志必须已开：`yabai -m config debug_output on`；注意 daemon 经 launchd 的 stdout 若被删过会写进已删除 inode → 需 `yabai --restart-service` 恢复）：

```bash
grep -nE "SPACE_DESTROYED|SPACE_CREATED|SPACE_CHANGED:|DAEMON_MESSAGE" /tmp/yabai_<user>.out.log | grep -v MOUSE
```

**实测时间线（2026-10-10）**：

```
DAEMON_MESSAGE: space --focus 2        ← 你的 front-switch 脚本（只切视图）
SPACE_CHANGED: 58                      ← id58 = display1 index2
... 全屏：SPACE_CHANGED: 1526           ← 全屏空间
SPACE_CHANGED: 50                      ← 退出全屏后系统直接切回 id50 = display1 index1
```
**关键**：58 → 50 这一步前后**没有任何 `window --space` 命令**。

**责任面（yabai 侧可能性已穷举）**：

| 路径 | 结论 |
|---|---|
| `window --space` 命令（`window_manager_send_window_to_space`） | 日志中未出现；且它只有两个调用者：message.c 的命令处理 + 规则（`apply_rule_effects`） |
| 规则指派空间 | 你的 yabairc 无 space 效果规则 |
| daemon 自动指派 | `space_manager_assign_process_to_space` / `..._to_all_spaces` 是**死代码**（无调用者） |
| SA 侧 | SA 只有 create/destroy/focus（space）与 focus（window），**没有"移动窗口到空间"的 opcode** |
| `SLS_SPACE_DESTROYED` / `view_destroy` | 只清理 yabai 内部模型，不碰系统窗口 |

→ **观察结论**：窗口回到 desktop 1 是系统在全屏空间销毁后的恢复结果；yabai 未发出任何搬移指令。

**处置**：属 macOS 侧（与 S9 的 `com.apple.spaces.plist` 布局损坏同属"系统空间恢复"问题 `[INFERENCE]`）；如需在 yabai 侧做绕过，需要在全屏空间创建时记住来源空间、销毁后把窗口送回——那是行为 hack，需用户明确同意。

**yabai 侧绕过（7.2.0 送窗口 / 7.2.2 视图跟随，2026-10-10）**

7.2.0 把窗口送回来源空间；视图跟随的第一版（7.2.1）用"重试抢回"，实测被否——**反复闪回**，且会与用户操作互相放大。

**归因证据**（2026-10-10 实测）：每一次 `SPACE_CHANGED: 50` 之前都紧跟一条客户端命令——

```
EVENT_HANDLER_DAEMON_MESSAGE: space --focus 1     ← 外部命令（front-switch 脚本或按键）
EVENT_HANDLER_SPACE_CHANGED: 50                    ← 它的效果
```

"切回第一个桌面"因此不是系统偷偷复位，而是**外部驱动**；daemon 自己调 `space_manager_focus_space()` 不会产生 `DAEMON_MESSAGE`，可据此区分两者。

**现设计（7.2.5）**：

| 规则 | 为什么 |
|---|---|
| 还原时只登记**一次**跟随意图（`view_follow_sid` + 待聚焦窗口） | 反复抢回 = 反复闪 |
| 空间变化时**只聚焦被还原的窗口**（`view_follow_focus_window()`），不切桌面 | 抢着切会插进用户 front-switch 脚本的判断窗口，脚本会再判一次并把视图拉回 → 来回跳 |
| 只有**没人**切视图时，yabai 才在 0.4 秒后补切一次（`view_follow_fire()`） | 兜底，通常因目标已可见而无动作 |
| 收到外部 `space …` 或 `window --focus/--space/--display` 命令 → **立刻放弃** | 用户/脚本在操作时绝不插手 |
| 目标已可见 / 超期 / 目标空间被销毁 → 安静退出 | 不做无谓动画 |

**被否掉的两版**（别再走回头路）：7.2.3/7.2.4 的"收到系统空间变化就立刻切"会与外部脚本互相放大；7.2.2 的"固定等 0.5 秒安静"对用户太慢。

**用户脚本侧被否掉的尝试**：加 `sleep 0.15` + "可见空间 1 秒内变过就跳过" → 实测**卡顿感**且**漏跳**（用户切 app 刚好紧跟在切桌面之后时被跳过）。正确分工是：yabai 只管窗口，视图交给脚本的即时路径。

**`~/.config/yabai/window_focused_event_script.sh` 最终形态（2026-10-10）**——与最初版本**只差一条规则**：可见性看【整个 app】（原版只看 `.[0]`＝创建最早的窗口，会在别桌面留着更早窗口时把你从当前桌面切走）；其余全部沿用最初：目标窗口 `.[0]`、`space --focus` + `sleep 0.1` + `window --focus`、**一次 `jq`**。

**聚焦时序（用户说明，2026-10-10，勿改）**：切桌面靠 `space --focus`；随后的 `window --focus` **不是为了切桌面**，而是因为目标桌面上可能有多个窗口，切换后**由 macOS 决定落在哪个 app 上**，不一定是想要的那个，所以必须显式再聚焦一次。`sleep 0.1` 是等切换过渡，属该设计的一部分。

> 我曾把它改成「立刻聚焦 + 0.3 秒后补一次」，被用户否掉并回退（2026-10-10）；动作三行保持与原版逐字一致。

**手感对齐证据**（影子 yabai，各 10 次）：最初 132 ms / 现在 130 ms；逐行结构差异仅 jq 过滤器与 `-n "$target_space"` 判断。**被否掉的三处改动**：① `sleep 0.15` + "空间刚变就跳过" → 卡顿 + 漏跳；② 拆两次 `jq` → +9 ms（中位 140 vs 131）；③ 目标窗口"优先 has-focus" → 跳向的窗口与最初不同（实测不可见窗口 has-focus 基本为 false，收益存疑）。备份仍在同目录 `window_focused_event_script.sh.bak`。
