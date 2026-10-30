# Active Context - yabai

## ✅ macOS 27.2 支持（7.2.7–7.2.13，2026-10-28，已真机验证）

- 系统 27.2（26B123）；Dock 2571.0.6.402 → **2571.1.32.402**，旧特征码大面积失配
- 事故：扫描窗口越过新 `__TEXT`（`0x2b0000 + 0x1286a0 > 0x3b9b80`）读进保护页 → Dock 崩溃循环；恢复：停 yabai → 移走 osax → `launchctl kickstart gui/$UID/com.apple.Dock.agent` → 重启
- 安全护栏：扫描一律钳制到 `__TEXT` 末尾，text 尾未知或 `scan_limit==0` 时 fail-closed；27.x 按 Dock 构建白名单（`2571.0.6.402` / `2571.1.32.402`），未知构建拒绝初始化
- 27.2 profile（arm64，构建锁定）：Spaces 单例槽 **0x329be0**；create helper **0x20ce00**；空数组单例槽 **0x2ef0d8**（`__DATA_CONST` GOT，`dyld_info -fixups` 证实绑定 `__swiftEmptyArrayStorage`）
- 能力实现：create（随机 UUID 身份）/ focus（纯 SLS）/ destroy（`CGSSpaceDestroy`）/ 跨屏 move（`CGSMoveManagedSpaceToDisplayIndex`）/ 同屏排序（`SLSTransaction*`）；跨 space window focus 的空间切换走 SA（7.2.14），窗口聚焦仍走 `_SLPS+AX`
- 握手：`OSAX_ATTRIB_REQUIRED` = ADD|REM|MOV；27.2 如实上报 SLS 实现的 REM/MOV；ADD 需 helper + Swift 桥 + 空数组单例齐全
- 真机验证：create 66/68/70/77/78；focus 1→66→1；move 77 display1↔2；排序 78 移到 index3；destroy 后 count 回 6、id 唯一
- 伪命中教训：`remove_space` 旧 pattern 在 27.2 命中 0x12dbcc **并非 removeSpace**（prologue 只保存 4 个参数）；pattern 命中 ≠ 函数身份
- 桌面编号：27.2 恢复**全局编号**；`~/.config/skhd/skhdrc` 已回滚为直接使用 N（备份 `skhdrc.bak-20261028-global-index`）
- 计划：`docs/plans/2026-10-28-macos-27.2-support.md`（completed）
- 发布：功能 `a0427be` / 版本 `6cd952d` / 手册 `5a53ab8`（ai-base）；dev `4aef480`/`c6bcce7`/`ff62fb3`；master `c35bbe0`/`0eb0cef`/`ac1aaa4`；三支已推送且与 origin 一致

## ✅ 27.2 全类型焦点切换（7.2.18，2026-10-29，用户验证）

- 根因：27 对应用/窗口激活的隐式 space 切换播放动画；Dock 日志确认来源是 `workspaces-auto-swoosh` 的窗口排序跟随
- 最终配置：`workspaces-auto-swoosh=false`（Dock 重启后生效）+ `skip_window_focus_animation=off`；Dock 不再切，yabai/前台脚本独占
- 7.2.15：实现 27 IOHID payload + companion 三阶段手势；7.2.17：等待 display 稳定、目标 space 可见后才聚焦，超时中止（替代 7.2.16 的动画中切换）
- 7.2.18：`skip_window_focus_animation` 恢复默认 off，避免手势与脚本 `space --focus` 互相触发（两个 APP 来回闪）
- 7.2.19（审查修复，源码已提交）：新增 `fast_window_switch`（默认 on），`skip_window_focus_animation` 恢复默认 off；前台切换优先 focused window、排除 minimized fallback、sticky 按可见处理；切换后最多 500ms 等 space 可见再 raise；恢复 Cmd+Tab `__fence`；删除 `process_manager_active_space_for_psn`；可见性抽成 `window_is_visible`，tests 3/3；构建 0 warning
- 2026-10-29 复测：重装后 Dock `workspaces-auto-swoosh=1`，与 fast path 竞争 → 间歇动画；已设为 0，Dock 于 22:10 重启后用户确认隐藏空间切换无动画；fast on / skip off / debug off
- 7.2.20（复审修复，源码已提交）：fast landing 在 `applications_to_refresh` 解析后执行；移除 `__pending_window_focus` 拦截；sticky 判断抽成 `window_is_sticky_effective`；分离 `skip`/`fast` 文档并注明无 SA 的 gesture fallback；tests 4/4；构建 0 warning
- 2026-10-30：R22 增加 Dock 设置生效检查；7.2.20 复审修复已完成源码、测试与文档，运行时待用户重启验证
- 7.2.21（deploy default，AI 分支专属，已提交）：`make deploy` 在 Accessibility 步骤后写入 `workspaces-auto-swoosh=0` 并重启 Dock，随后加载 SA/启动服务；版本 7.2.21，tests 4/4，build 0 warning；README/CHANGELOG/man 已同步；ai-base `928c024`（deploy/docs）/`9088d9c`（version）；dev/master 仍有旧 deploy target，但无 7.2.21 改动
- 7.2.22（cleanup，已提交 ai-base/dev/master）：macOS 更新后系统已修复全屏退出落点，删除 `fullscreen_restore` / `view_follow` workaround；tests 4/4，build 0 warning；code `9916eeb` / version `c70160c`；dev `581aa39`/`c944278`；master `3f8cdfe`/`09ba6a6`；AI `5685751`；三支本次推送
- 2026-10-30 发布提交：ai-base `87d35c7`（code）/`d96ed38`（docs）/`3089347`（7.2.20）/`a710a3c`（AI）；dev `fa4893a`/`4741e79`/`95c2f88`；master `2d10a3f`/`32bbbdf`/`5e7d2db`；origin 三支一致，工作树 clean
- 实测：直接 `space --focus` 无横移；最终配置下用户确认无问题；仍需长期观察
- 计划：`docs/plans/2026-10-29-macos27-iohid-gesture.md`（completed）
- 发布：功能 `c9c1ff2` / 版本 `5fdb079`（ai-base）；dev `cff32ad`/`f11c765`；master `1cce764`/`ffb5952`；AI 记录 `f4fa857`
- 后续：Dock 启动/重开路径动画已完成调查，结论见下节

## ✅ REA/Ghidra provider + reverse-engineering skill v3（2026-10-29）

- `~/.config/opencode/skills/reverse-engineering/SKILL.md` v3：任何 rea 调用前强制加载 `reverse-engineer-anything`；明确 REA 技能优先于本机事实
- Ghidra：独立 12.1.4 为 REA 唯一支持版本；Homebrew 12.2 不可指向；`~/.zprofile` 已同步，`doctor` healthy，`binary_session` 显示 12.1.4
- 新增 §1a 版本漂移：用前/每月 `npm view rea-agents version` + doctor；新版支持新 Ghidra 时 side-by-side 安装并重启
- 验证：baseline 子代理误答 Homebrew 路径且无升级流程；GREEN 子代理正确选 12.1.4、先读 REA 技能、给出 side-by-side 升级
- 待办：无

## 🔬 Dock 平移动画调查（2026-10-29，Dock 参数层已排除）

- Dock `2571.1.32.402` arm64e；Cmd+Tab 路径 `FUN_100126768` 在 `0x1268dc` 置 `x1=1` 后调 `FUN_100188858(space,x1,x2,x3,x4)`
- 已否定：launch closure `x1=0`、Cmd+Tab `0x1268dc x1=0`、`x2=1`、`FUN_1000c27c8` 内 `isAnimating=false`
- 2026-10-29 追加 A/B：Dock 点击 `magpie(space2) -> cmux(space1)`，30fps 录制；`0x1000c4878` 的 `mov w2,#1` 运行期改为 `mov w2,#0`（`SLSTransactionSetManagedDisplayIsAnimating`），readback 确认，**动画仍存在**；该 flag 未证明是开关（断点命中未完成：暂停 Dock 后 AX 点击无法进入）
- `WASpaceFrameAnimation` 在 Dock `NSClassFromString` 为 nil；Dock 导入 `WindowManager.TransitionAnimation`，`WindowManager`/`SkyLight` 虽加载在 Dock，但动画类不在 Dock 注册
- 结论：**撤回此前“yabai 绝对做不到”的结论**；Dock 参数层未被证明可修，WindowServer/WindowManager 的 transition 入口尚未定位，需 root attach 或更多静态取证
- 用户拒绝 front-switch/脚本 workaround；源码已回退 7.2.18 / OSAX 2.1.41，未安装
- 计划：`docs/plans/2026-10-29-dock-space-transition-animation.md`（closed；7.2.19 运行时已验证，7.2.20 source 待运行时验证）
- 2026-10-29 18:48 事故：按建议直接 `sudo lldb -p WindowServer` 导致 WindowServer SIGSTOP、GUI 冻结并由系统自动重启；无持久修改，`/tmp/ws-survey.log` 随重启清除；**禁止再次 attach WindowServer**，后续只能非停止采样或带 watchdog 的短时 attach
- 2026-10-29 18:53 基线恢复：安装 `yabai-v7.2.18` / OSAX 2.1.41；源码 diff 空；无 LLDB 残留；WindowServer/Dock 正常
- 2026-10-29 native fast landing v2（已部署）：按 application window visibility 找目标窗口，再 `space_manager_focus_space(sid)` + `window_manager_focus_window_with_raise`；不再依赖 PSN space
- 2026-10-29 v2 实测（用户已部署）：debug 日志确认 `fast front switch` 每步返回 0，`SPACE_CHANGED` 正常；WindowServer 滑动仍存在；实际开启 `ReduceMotionEnabled=1` 也无法消除（已恢复 0）；native fast landing 只能快速落位，不能移除系统滑动
- 2026-10-29 决策：保留 native fast landing，接受 WindowServer 系统滑动；debug off；7.2.20 复审修复后 skip off / fast on；源码未提交，版本 7.2.20；运行时烟雾待用户重启验证

## ✅ 7.2.14 同 APP 跨 desktop 焦点落点（已完成，含在 7.2.18）

- 事实：`opt+shift+tab` → `same_app_window_forward.sh` 只发 `window --focus`；daemon 该命令只做 SLPS/AX 聚焦，27.2 对“窗口激活引发的隐式 space 切换”播放横移动画（不是脚本问题）
- 对照：`cmd+tab` → `window_focused_event_script.sh` 先 `space --focus`（SA/SLS 直切）再 `window --focus` → 立即落点
- 修复：`message.c` 的 `window --focus` 在目标 space 不可见且窗口未最小化时，先 `space_manager_focus_space(sid)`（与 `space --focus` 同一路径），再聚焦窗口；SA 失败/MC/动画中回退原生切换
- 版本：7.2.14（OSAX 2.1.41 不变）；编译 0 警告、`make -C tests` 2/2
- 用户反馈（2026-10-29）：window focus 本身就是触发点，不允许把修复解释成"脚本只发 window --focus"的脚本层问题
- 现场：7.2.14 已包含在 7.2.18，用户验证通过，不再单独部署
- 状态：✅ 完成（`window --focus` 预切换保留）
- 提交：ai-base 功能 `9e7bcb8` / 版本 `04d4d8c`；dev `b0c71a8`/`24c3376`；master `27ca10e`/`d1aa085`；代码内容一致

## ✅ 7.2.6 空间身份修复 —— 主屏失背景已闭环（2026-10-23）

- **现象**：开机后主屏无壁纸、Mission Control 只见 1 个桌面（无桌面方块）；建/删桌面后反复复发；窗口上下窜动
- **取证**：关机前 `managed space order: [50,3258,58,81,90,84,72,2380]`（健康）→ 开机 `[6,6,6,6,6,6,6]`；yabai 比损坏日志晚 4 秒启动（非开机写入者）
- **决定性对照**：系统 Mission Control “+” 建的空间 id 33 → `uuid=442D311F…`（唯一）；yabai 建的空间 id 26 → `uuid=37D8832A…`（显示器 UUID）
- **根因**：macOS 27 `do_space_create` 把显示器 UUID 当新空间身份传给 Dock helper；helper 原样写入 `CGSSpaceCreate` 的 `@{type,uuid,pid}` → 同显示器所有 yabai 空间共享一个身份 → `com.apple.spaces` 按身份持久化 → 开机恢复把重复身份全部映射到同一 id → 桌面层取不到壁纸
- **旧结论作废**：S9 的“纯系统侧 / `space --create` 可修复”是错的——create 本身在污染身份，越修越脏（更正见 `domains/space-management/scenarios.md` S9）
- **修复**（7.2.6 / OSAX 2.1.34，编译 0 警告）：create 改传 `CFUUIDCreate` + `CFUUIDCreateString` 生成的新 UUID；创建后用 `SLSCopyManagedDisplayForSpace` 校验落点（不符打 WARNING）；Swift 桥不可用则中止
- **实测**：`space --create` 返回 id 40、`uuid=ACE42D27…`（唯一）；清理 `com.apple.spaces` + 注销/重启后三台显示器 order 为 `[1]` / `[6]` / `[7]`，`query --spaces` count=3 unique=3，壁纸恢复、窜动消失
- **处置要点**：删除域后 plist 变 42 字节空壳（`{}`）属正常；必须在注销/重启**之前**确认域为空，否则 WindowManager 会按旧模型重建
- 计划：`docs/plans/2026-10-23-space-create-uuid-identity.md`（completed）

## 当前工作焦点

当前工作焦点：7.2.22 全屏还原 workaround 已删除并提交 ai-base（`9916eeb` / `c70160c`），待 cherry-pick 与推送；7.2.21 deploy 已推送 ai-base，dev/master 保留旧 target。

## 已知设计限制（不处理）

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字（1 秒覆盖） | Apple 未暴露相关 API，无完美解法 |

## 📚 历史锚点

- 7.2.0–7.2.5 全屏还原 workaround 已于 7.2.22 退役，历史见 `docs/plans/2026-10-10-fullscreen-restore.md`
- macOS 27 空间创建三代实现的完整历程：`progress.md` Phase 39 + `domains/space-management/principles.md`
- macOS 26 世代细节：`archive/activeContext-2026-10.md`，领域结论见 `domains/`
