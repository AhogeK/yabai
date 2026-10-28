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
- 实测：直接 `space --focus` 无横移；最终配置下用户确认无问题；仍需长期观察
- 计划：`docs/plans/2026-10-29-macos27-iohid-gesture.md`（completed）

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

无进行中任务。macOS 27.2 支持（7.2.13）已完成并真机验证；后续按日常使用观察。

## 已知设计限制（不处理）

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字（1 秒覆盖） | Apple 未暴露相关 API，无完美解法 |

## 📚 历史锚点

- 7.2.0–7.2.5 全屏还原与视图跟随：`progress.md` Phase 40（含一次 `space_window_list()` 池内存误 free 的崩溃事故与教训）
- macOS 27 空间创建三代实现的完整历程：`progress.md` Phase 39 + `domains/space-management/principles.md`
- macOS 26 世代细节：`archive/activeContext-2026-10.md`，领域结论见 `domains/`
