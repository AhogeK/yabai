# scenarios — 触发场景 → 判断 → 动作

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：含推论
> **来源**：S1 排查顺序已验证；S4（ivar 改名）与 S6 为推论，待实测

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

## S8. 按编号操作桌面时打到了别的显示器（macOS 27.0.1+）

**判断**：多显示器 + 按数字选择器（`space --focus N` / `window --space N`），发现生效的是另一台显示器上的桌面。

**动作**：
1. 记住 yabai 的 N 是**全局序**（display 1 全部 → display 2 全部 → …），而 Mission Control 的编号是**每显示器独立**；
2. 需要"当前显示器的第 N 个"时用：`yabai -m query --spaces --display | jq -r '.[N-1].index'` 取到 yabai 的 index 再用；
3. 校验方法：`yabai -m query --spaces | jq '[.[] | {index, display}]'`（对照 `yabai -m query --displays`）。

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
