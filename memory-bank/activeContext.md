# Active Context - yabai

## Current Work Focus

**Makefile deploy 修复 (2026-03-30 23:30)**

---

## 📋 最新变更

**修复**: makefile deploy 打开 Accessibility 直接导航

**问题**: `@open -a "System Settings"` 只打开设置，不导航到具体页面

**修复**: 使用 URL scheme 直接打开 Accessibility
```makefile
@open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

**提交**: `d499a53 fix(makefile): open Accessibility directly in System Settings`

---

**透明度问题已由用户解决**: 透明度代码位置问题导致窗口焦点问题，用户已自行修复

---

**OSAX 文件同步 dev → ai-base (2026-03-30 23:10)**

---

## 📋 之前变更

**同步**: 从 dev 分支同步 `src/osax/arm64_payload.m` 和 `src/osax/payload.m`

**变更内容**:
- 添加 control-flow fingerprint 优先查找 DPPM singleton
- DPPM pattern 字节修正 (第二字节放宽为通配符)
- 恢复 macOS 26 的 add_space_pattern (之前返回 NULL)
- 添加 macOS 26.4 特定的 add_space_pattern 变体

**提交**: `6e69c07 fix(osax): prioritize control-flow fingerprint for DPPM singleton`

---

**DPPM Scanner False Positive Fix (2026-03-30)**

---

## 📋 之前变更

**修复**: DPPM scanner 消除 false positive 匹配

**问题根因** (用户日志分析):
- Decoded offset: `0x410bb8` (WRONG - random object)
- Expected offset: `0x4880d0` (DPPM singleton from Ghidra)
- 原因: 前 6 指令是通用 ObjC Setter 模板 - Dock 中有数百个匹配
- 结果: 错误对象传给 Mission Control → 类型不匹配 → Dock 崩溃循环

**解决方案**: 添加 behavioral fingerprint (cbnz + str) 验证

**新增验证** (10 指令完整验证):
| 指令 | 验证内容 | 目的 |
|------|----------|------|
| ins[0-5] | Setter prologue | 基础锚点 |
| ins[6] | ADRP + 提取 dest register | 页基址加载 |
| ins[7] | LDR + 提取 base/target register | singleton 值加载到 x0 |
| ins[8] | 👑 CBNZ x0 | nil 检查 → 非 nil 则崩溃 |
| ins[9] | 👑 STR x19 | nil 时存储 retained 对象 |

**数据流验证**:
```
adrp_rd == ldr_rn  → LDR 使用 ADRP 计算的地址
ldr_rt == 0        → LDR 加载值到 x0
cbnz_rt == 0       → CBNZ 检查刚加载的值 (x0)
str_rn == adrp_rd  → STR 写回同一内存地址 (singleton)
str_rt == 19       → STR 写入 x19 (retained 对象)
```

**预期日志**: `[yabai-sa][DPPM] SUCCESS: Decoded dppm ptr=0x... (offset 0x4880d0)`

**状态**: ✅ 编译成功，无警告，待用户测试

**文件**: `src/osax/payload.m` (+45 行，-28 行)

---

**DPPM Dynamic Address Decoding 实现 (2026-03-30)**

---

## 📋 之前变更

**实现**: DPPM (DesktopPicturePolicyManager) 动态地址解码

**背景**: 用户通过 Ghidra 逆向分析发现：
- `DAT_1004880d0` 是 DPPM singleton 全局变量
- 加载方式为 `adrp + ldr` (不同于 Spaces singleton 的 `adrp + add`)
- `setDesktopPictureManager:` 函数 (`FUN_10011cd90`) 有独特的 5 指令序言

**新增函数**:
| 函数 | 用途 | 关键点 |
|------|------|--------|
| `decode_adrp_ldr_pair()` | 解码 ADRP+LDR 指令对 | LDR offset 在 bits 10-21，scale by 8 |
| `find_dppm_singleton_instructions()` | 查找 setDesktopPictureManager 函数 | 使用 10 指令 + behavioral fingerprint |

**预期结果**: 解码地址 offset 应为 `0x4880d0`

**文件**: `src/osax/payload.m`

---

**DOUBLE-ANCHOR Search 实现 (2026-03-30 06:00)**

---

## 📋 之前变更

**问题**: CALLER-BASED Search 仍匹配错误 singleton (offset 0x488010)，应为 0x488028

**根因**: Pattern matching 在复杂 binary 中太宽松，匹配到 Mach-O header string "MUTZ"

**修正**: DOUBLE-ANCHOR Search 方案

| 改进点 | CALLER-BASED | DOUBLE-ANCHOR |
|--------|--------------|---------------|
| Search target | Pattern matching (adrp+add+mov+bl) | BL instruction to addSpace |
| Anchor type | Loose pattern | Absolute address (0x1f07d8) |
| Backward search | None | Search -1 to -10 for adrp+add |
| Precision | Medium (matched wrong code) | Extremely high (caller binding) |
| Expected offset | `0x488010` (wrong) | `0x488028` (correct) |

**Double-Anchor Logic**:
```
1. Search for BL instruction with target = space_create_entry_fp (0x1f07d8)
2. Once found, search BACKWARDS 10 instructions for nearest adrp+add pair
3. This pair loads the CORRECT singleton before calling addSpace
```

**状态**: ✅ 编译成功，待用户测试

---

**代码审查: ai-base 分支透明度逻辑分析 (2026-03-29)**

---

## 📋 审查结果摘要

**审查范围**: commits `6ea7f16` + `07a2299` (opacity retry 机制)

**整体结论**: 代码逻辑正确，但有 4 个问题需关注

| 问题 | 严重性 | 核心点 |
|------|--------|--------|
| 问题一 | 🔴 中等 | `opacity` 参数被忽略，rule vs global 语义不清 |
| 问题二 | 🟡 轻微 | focus 时 `active_window_opacity` 被 retry 覆盖 |
| 问题三 | 🟡 轻微 | 缺少 workaround 原因注释 |
| 问题四 | 🟡 轻微 | dispatch block 窗口销毁后 wid 仍被使用 |

**核心决策点**: 当窗口同时有 rule opacity (`window->opacity != 0.0f`) 和系统 active_window_opacity 时，期望的最终行为是什么？

---

## ✅ 语义已确认 (2026-03-29 21:45)

**决策**: 选项 A — rule opacity 是强制静态值，bypass 整个 active/normal 系统

**Plan Agent 输出**:
- 推荐方案: **Option D (Hybrid)**
- 新增函数: `window_manager_enforce_rule_opacity()`
- 修改文件: `src/event_loop.c`, `src/window_manager.c`
- Session ID: `ses_2c61aac2dffet8VeB4GjbdfZc7`

**已完成任务** (2026-03-29 22:00):
- [x] Task 2: Implementation ✅
- [x] Task 3: Build Verification ✅ (无警告)
- [ ] Task 4: Git Commit (需用户授权)

**变更摘要**:
| 文件 | 变更 |
|------|------|
| `src/window_manager.c` | 新增 `window_manager_enforce_rule_opacity()` + WHY 注释 |
| `src/window_manager.h` | 添加函数声明 |
| `src/event_loop.c` | 修改 `window_did_receive_focus` 检查 rule opacity |

**解决的问题**:
1. ✅ `opacity` 参数不再被忽略
2. ✅ `active_window_opacity` 不再在无效时传递
3. ✅ 添加 WHY 注释解释 macOS 行为
4. ✅ dispatch block 添加生命周期检查

---

## ⚠️ 已知遗留问题 (设计限制/权衡)

| # | 问题 | 严重性 | 说明 | 是否需处理 |
|---|------|--------|------|-----------|
| 1 | "同 space 才处理失焦窗口"限制 | 🟡 设计 | `window_space(focused_window->id) == window_space(window->id)` 条件导致跨 space 切换时失焦窗口透明度不恢复。这是原版设计，非本次引入。 | ❌ 保持原样 |
| 2 | 重试 10 次魔法数字 | 🟡 权衡 | `for (int i = 1; i <= 10; i++)` + `0.1s` = 1秒覆盖。高负载时可能不够。无完美解法（Apple 未暴露相关 API）。 | ❌ 保持原样 |
| 3 | `window_manager_set_opacity()` 的 0.0f 分支 | 🟢 分离 | 该函数有 `opacity == 0.0f` 时的 fallback 逻辑，与新函数 `window_manager_enforce_rule_opacity()` 路径分离，互不干扰。 | ✅ 已清晰分离 |

---

**macOS 26 Space Creation - Phase 31: 多显示器支持已实现**

---

## ✅ 多显示器支持实现 (2026-03-29 02:00)

**添加的功能**：
- `display_id_for_uuid()` 辅助函数 - 使用 IOKit 遍历显示器并匹配 UUID
- 修改 `do_space_create()` 使用 `display_id_for_uuid(display_uuid)` 替代 `CGMainDisplayID()`

**问题发现** (2026-03-29 02:30):
- ❌ IOKit 在 Dock 沙箱下静默返回 `MACH_PORT_NULL`
- ❌ `CGDisplayIOServicePort()` 不可用
- ✅ 修复方案：改用 `CGDisplayCreateUUIDFromDisplayID()` (纯 CoreGraphics API)

**技术细节**：
```c
// 之前（错误 - IOKit 在沙箱下不可用）：
io_service_t service = CGDisplayIOServicePort(displays[i]);  // 返回 0
CFTypeRef uuid_ref = IORegistryEntryCreateCFProperty(...);  // 静默失败

// 现在（正确 - 纯 CoreGraphics API）：
CFUUIDRef uuid_ref = CGDisplayCreateUUIDFromDisplayID(displays[i]);  // 沙箱可用
```

**修复完成** (2026-03-29 03:00):
- ✅ 替换为 `CGDisplayCreateUUIDFromDisplayID()` (纯 CoreGraphics API)
- ✅ 移除 `#include <IOKit/IOKitLib.h>`
- ✅ 移除 `-framework IOKit`
- ✅ 添加警告日志用于调试

**待测试**：
- 多显示器场景下 space 创建在正确显示器
- 单显示器场景正常工作

---

## ✅ 代码清理完成 (2026-03-29 00:05)

**已删除** (~592 行)：
- 所有 `debug_log()` 调用
- 所有 `NSLog` 调试语句
- 所有 `hooked_` 函数
- 所有 hook 基础设施
- `attempt_eager_manager_capture()`
- `get_wallpaper_manager_for_create()`
- 所有 wallpaper manager hooks
- 所有 space creation entry hooks
- 所有 notification hooks
- `/tmp/yabai-sa-debug.log` 写入代码

**文件变化**：
- `payload.m`: 1858 行 → 1266 行
- `arm64_payload.m`: 保留核心宏定义
- `makefile`: 删除 `-framework AppKit`

## ✅ 文档清理完成 (2026-03-29 00:15)

**已删除** (13 个文件)：
- `lldb-output.txt`, `02-static-analysis.md`, `04-experiment-log.md`
- `all-lldb-debug-log.txt`, `architect-review-2026-03-28.md`
- `architect-review-request-2026-03-27.md`, `dtrace-space-precise.d`
- `dynamic-analysis-report-2026-03-28.md`, `LLDB-GUIDE.md`
- `OPERATING-GUIDE.md`, `plan-static-analysis-add-space.md`
- `space_debug.lldb`, `space-creation-impasse-analysis-report.md`
- `static-analysis-report-2026-03-28.md`

**保留** (核心分析文档)：
- ✅ `lldb-analysis.md` (74KB - 完整 LLDB 分析)
- ✅ `lldb-analysis2.md` (10KB - 第二次 LLDB 会话)

**构建结果**：✅ 编译成功，无警告

---

## Phase Status

| Phase | 状态 | 结果 |
|-------|------|------|
| Phase 1-3 | ✅ COMPLETE | 代码实现完成 |
| Phase 25-27 | ✅ COMPLETE | 清理完成 |
| Phase 27.1 | ✅ COMPLETE | Bug 修复（地址重复计算） |
| Phase 28 | ❌ FAILED | 测试失败 - 函数内部崩溃 |
| Phase 29 | ✅ COMPLETE | 宏修复（原子 asm + retain/release） |

---

## 测试结果 (2026-03-29 00:14)

**成功的部分**：
- ✅ `spaces_singleton=0x89ec901e0` 读取成功（非 nil）
- ✅ 地址计算正确
- ✅ 诊断日志打印正常

**失败的部分**：
- ❌ 没有 `space_create_entry returned` 日志
- ❌ 函数内部仍然崩溃

**根因分析** (架构师):
1. **宏分离问题** - `asm` + `((void(*)())func)()` 是两个语句，编译器可以中间插指令
2. **缺少 retain** - 原生调用有 `objc_retain`，我们直接传原始指针

**修复方案** (2026-03-29 00:35):
1. ✅ 合并到一个 `asm volatile` 块，使用 `blr` (寄存器间接跳转)
2. ✅ 添加 `objc_retain`/`objc_release` 包裹调用
3. ✅ 正确的 clobber 列表（所有 caller-saved 寄存器 + x30）

**测试成功** (2026-03-29 01:02):
```
[SPACE] singleton=0xc00870480 func=0x104c787d8
[SPACE] calling space_create_entry(display_id=1) retained=0xc00870480
[SPACE] space_create_entry returned  ← 第一次成功返回！
```
✅ Dock 不再崩溃
✅ space 创建成功
✅ 历史性突破！

**遗留问题** (2026-03-29):
- ❌ 多显示器支持 - `CGMainDisplayID()` 硬编码，永远创建在主显示器
- ✅ 修复方案：添加 `display_id_for_uuid()` 辅助函数，遍历显示器匹配 UUID

```bash
# 1. 重启 yabai
yabai --restart-service

# 2. 等待 5 秒
sleep 5

# 3. 测试 space 创建
yabai -m space --create

# 4. 验证 Mission Control 中出现新 space
```

---

## 关键函数偏移 (macOS 26.4 Tahoe)

| 偏移 | 功能 | 状态 |
|------|------|------|
| `0x1f07d8` | 顶层创建入口 | 已实现，待验证 |
| `0x1eb33c` | 数组遍历 | 已确认 |
| `0x285564` | 空间处理 + CGS | 已确认 |
| `0x19e150` | DPPM 壁纸创建 | 已确认 |

---

## 相关文件

- `src/osax/payload.m` - 主 payload
- `src/osax/arm64_payload.m` - 偏移定义
- `docs/macos26/lldb-analysis.md` - LLDB 分析
- `docs/macos26/lldb-analysis2.md` - 第二次 LLDB 会话