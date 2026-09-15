# Active Context - yabai

## Current Work Focus

**macOS 27.0 (26A428) 空间创建 / 窗口聚焦修复 — 代码完成，待现场验证 (2026-09-15)**

---

## 📋 本次变更 (macOS 27)

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

**验证**: 静态完成（pattern 命中/唯一性/全局解码 + 双架构编译通过）；动态待用户安装后确认

**文档**: `docs/reverse-engineering-macos27-space-create.md`（含 dyld cache 提取与 pattern 校验脚本）

---

## ⚠️ 待现场验证（用户执行）

1. `yabai --load-sa`（SA 版本不匹配会自动重装并重启 Dock）
2. `log show --last 5m --predicate 'process == "Dock"' | grep yabai-sa`
   期望含 `[yabai-sa][WM] WindowManager entry points resolved (...)`
3. `yabai -m space --create` → 期望 `[yabai-sa][WM] ... returned (spid=<非0>, error=0x0)`

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
