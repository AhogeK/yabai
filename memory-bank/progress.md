# Progress - yabai

## Current Phase: macOS 26 Space Creation - Phase 28 (等待用户测试)

---

## Phase History

### Phase 1-3: 分析与实现 ✅ COMPLETE

- **Phase 1**: 静态分析 - 5 个函数偏移 (0x1f07d8, 0x1eb33c, 0x285564, 0x143e1c, 0x19e150)
- **Phase 2**: 动态分析 - 捕获调用链 `0x1f07d8 → 0x143e1c → 0x1eb33c → 0x285564`
- **Phase 2.5**: 架构决策 - 选择选项 A2 修正版 (直接调用 0x1f07d8)
- **Phase 2.6**: Hook 实现 - 添加 `get_space_create_entry_offset()`
- **Phase 2.7**: 验证 x0 参数 - 直接调用方案实现
- **Phase 3**: 完整实现 - `do_space_create_macos26()` 调用 0x1f07d8

### Phase 3.1: 类型错误修复 ✅ COMPLETE (2026-03-28 17:53)

- **问题**: 传递全局 `Spaces` 单例导致 Dock 崩溃
- **修复**: 使用 `display_space_for_display_uuid()` 获取 per-display 实例
- **文件**: `src/osax/payload.m` lines 1584-1606

### Phase 4: 最终验证 ❌ FAILED → Phase 28

- 多次尝试传递不同参数类型均崩溃
- 根本原因分析进行中

### Phase 25-27: 清理 ✅ COMPLETE (2026-03-29)

- **Phase 25**: 删除 `-framework AppKit`, 编译成功
- **Phase 26**: 删除所有调试代码 (debug_log, NSLog, hooked_ 函数)
- **Phase 27**: 删除 13 个过时文档，保留 lldb-analysis.md

### Phase 27.1: Bug 修复 ✅ COMPLETE (2026-03-29 00:30)

**修复的问题**：
1. **地址重复计算** - 改用 `space_create_entry_fp`（已在 `init_instances` 中预计算）
2. **地址计算错误** - 修复为 `baseaddr + 0x488028`
3. **缺少诊断日志** - 添加 4 个 NSLog 用于调试

**代码变化**：
```c
// 之前（错误）：
uint64_t space_create_addr = base_addr + image_slide_val + 0x1f07d8ULL;

// 现在（正确）：
uint64_t space_create_addr = space_create_entry_fp;  // 直接使用预计算的指针
```

**文件变化**：`payload.m` +14 行，-6 行

### Phase 28: 测试验证 ❌ FAILED (2026-03-29 00:14)

**测试结果**：
- [x] `spaces_singleton` 读取成功（非 nil）✅
- [x] 地址计算正确 ✅
- [ ] **函数内部仍然崩溃** ❌

**新发现**：
- 原生调用前有 `objc_retain(Spaces 单例)`
- 当前实现直接传原始指针，没有 retain
- 可能是崩溃根因

### Phase 29: 宏修复 ✅ COMPLETE (2026-03-29 00:35)

**修复内容**：
1. ✅ 合并 `asm` + 函数调用为一个原子 `asm volatile` 块
2. ✅ 使用 `blr` (寄存器间接跳转) 替代 `bl`
3. ✅ 添加 `objc_retain`/`objc_release` 包裹调用
4. ✅ 正确的 clobber 列表（所有 caller-saved + x30）

**文件变化**：
- `arm64_payload.m`: 宏定义重写
- `payload.m`: 添加 retain/release

**编译结果**：✅ 成功，无警告

### Phase 30: 最终测试验证 ✅ SUCCESS (2026-03-29 01:02)

**历史性突破**：
```
[SPACE] singleton=0xc00870480 func=0x104c787d8
[SPACE] calling space_create_entry(display_id=1) retained=0xc00870480
[SPACE] space_create_entry returned  ← 第一次成功返回！
```

**验证结果**：
- [x] `sudo make install` ✅
- [x] `yabai --restart-service` ✅
- [x] `yabai -m space --create` 测试 ✅
- [x] `space_create_entry returned` 日志出现 ✅
- [x] Dock 不再崩溃 ✅
- [x] Mission Control 显示新 space ✅

**技术突破**：
1. 原子 `asm volatile` 块防止编译器插入指令
2. 使用 `blr` (寄存器间接跳转) 替代 `bl`
3. 添加 `objc_retain`/`objc_release` 匹配原生调用
4. 正确的 clobber 列表（所有 caller-saved + x30）

**这是第一次成功调用 `0x1f07d8` 且 Dock 没有崩溃！** 🎉

### Phase 31: 多显示器支持 ⚠️ PARTIAL (2026-03-29 02:00)

**已实现**：
1. ✅ 添加 `display_id_for_uuid()` 辅助函数
2. ✅ 使用 `CGGetActiveDisplayList()` 遍历所有显示器
3. ✅ 使用 `CFEqual()` 匹配 UUID

**问题发现** (2026-03-29 02:30):
- ❌ `CGDisplayIOServicePort()` 在 Dock 沙箱下返回 `MACH_PORT_NULL`
- ❌ `IORegistryEntryCreateCFProperty()` 静默失败
- ❌ 导致永远 fallback 到 `CGMainDisplayID()`（主显示器）

**修复方案**：
1. 改用 `CGDisplayCreateUUIDFromDisplayID()` (纯 CoreGraphics API，沙箱可用)
2. 移除 `#include <IOKit/IOKitLib.h>`
3. 移除 `-framework IOKit`

**修复完成** (2026-03-29 03:00):
- ✅ 替换为 `CGDisplayCreateUUIDFromDisplayID()` (纯 CoreGraphics API)
- ✅ 移除 `#include <IOKit/IOKitLib.h>`
- ✅ 移除 `-framework IOKit`
- ✅ 添加警告日志用于调试

**编译结果**：✅ 成功，无警告

**待测试**：
- [ ] 多显示器场景下 space 创建在正确显示器
- [ ] 单显示器场景正常工作
- [ ] 提交并推送

### Phase 31: 多显示器支持 ✅ COMPLETE (2026-03-29 01:30)

**实现内容**：
1. ✅ 添加 `display_id_for_uuid()` 辅助函数 - 使用 IOKit 遍历显示器并匹配 UUID
2. ✅ 修改 `do_space_create()` 使用 `display_id_for_uuid(display_uuid)` 替代 `CGMainDisplayID()`
3. ✅ 添加 IOKit framework 到 makefile
4. ✅ 编译成功，无警告

**技术细节**：
- 使用 `CGGetActiveDisplayList()` 枚举所有显示器
- 使用 `CGDisplayIOServicePort()` 获取 IOKit service（已弃用但仍可用）
- 使用 `IORegistryEntryCreateCFProperty()` 获取 `IODisplayUUID`
- 使用 `CFEqual()` 比较 UUID 字符串
- 找不到匹配时回退到 `CGMainDisplayID()`

**文件变化**：
- `src/osax/payload.m`: +25 行（辅助函数）+ 1 行（include）+ 1 行（函数调用）
- `makefile`: +1 行（-framework IOKit）

**待测试**：
- [ ] 多显示器场景测试

---

## Key Findings

### 架构分离 (macOS 26)

```
"+" 按钮 → 0x1f07d8 (顶层入口, 分配对象)
         → 0x143e1c (内部: 数组追加 + CGS 注册)
         → 0x1eb33c (遍历 display spaces)
         → 0x285564 (CGSMoveManagedSpaceToDisplayIndex)
         → addSpace:forDisplayUUID: (壁纸创建)
```

### 关键发现

- `0x1f07d8` 是 Swift 方法，需要 `Spaces` 单例作为 self
- 传递错误的类型会导致 Dock 崩溃
- 调用顶层入口应自动触发结构和视觉两层

---

## Completed

- [2026-03-30 04:50] **修正锚点掩码（支持浮点寄存器 stp）** 🚧
  - **问题**: 原代码检查通用寄存器掩码 `0xad...`，实际是浮点寄存器 `0x6d...`
  - **修正**:
    - 锚点检测改为循环 `j=1..5`，接受 `0xad...`、`0x6d...`、`0xa9...` 任意 stp
    - 扫描窗口：3MB → 4MB
    - 内层循环：`i=2..15` → `i=1..20`
    - 新增验证：`adrp_rd == add_rn`（目标寄存器一致）
  - **状态**: 已编译，待用户测试
  - **文件**: `src/osax/payload.m`

- [2026-03-30 03:30] **实现动态 ADRP+ADD 地址解码（修正版）** 🚧
  - **状态**: 已实现，待用户测试
  - **新增函数**:
    - `decode_adrp_add_pair()`: 修正符号扩展逻辑（bit 20 为符号位）
    - `find_spaces_singleton_instructions()`: 使用 `pacibsp+stp` 锚点精确定位
  - **关键改进**:
    - 锚点 1: `pacibsp` (0xd503237f) - 函数入口签名
    - 锚点 2: `stp d9,d8` + `stp x24,x23` - 唯一标识 HotCorners::_handleEvents
    - 扫描范围：3MB 窗口
    - 日志输出：打印匹配的指令供 Ghidra 验证
  - **文件**: `src/osax/payload.m` (+66 行，-2 行)
  - **编译**: ✅ 无警告
  - **待办**: 用户需测试并验证日志输出

- [2026-03-30 02:30] **提交逆向工程文档** ✅
  - `docs/my-reverse-report.md`: macOS 26 Space 创建完整技术报告 (39KB)
  - `docs/my-reverse-engineering-learn.md`: 逆向工程研究方法指南 (70KB)
  - 提交：`b772f22`
  - 推送：`git push -u origin ai-base` ✅

- [2026-03-30 02:25] **清理 commit message 签名** ✅
  - 移除内容：`Ultraworked with [Sisyphus]...` 和 `Co-authored-by: Sisyphus...`
  - **master**: 37b25e8, c9a83d5 (原 41a8a8a, f79cd13)
  - **ai-base**: eefa78e (原 ff2f1b0)
  - **dev**: 无需清理（已干净）
  - 推送：`git push --force-with-lease` ✅

- [2026-03-30 02:20] **修正所有分支版本至 7.1.19** ✅
  - **master**: 
    - 回滚到 5821619 (v7.1.18)
    - 单独提交：f79cd13 (window_manager.c 修复)
    - 单独提交：41a8a8a (版本 bump)
    - 推送：`git push --force-with-lease origin master` ✅
  - **dev**:
    - 修正 src/yabai.c: PATCH 18 → 19
    - 修订提交：843e291 (原 bcffff1)
    - 推送：`git push --force-with-lease origin dev` ✅
  - **ai-base**:
    - 版本同步：ff2f1b0
    - 推送：`git push -u origin ai-base` ✅
  - **结果**: 所有分支 PATCH=19，版本统一 ✅

- [2026-03-30 02:00] **更新 dev 分支版本至 7.1.19** ✅
  - CHANGELOG.md: 添加 7.1.19  release note
  - scripts/install.sh: VERSION="7.1.19"
  - 新 commit: `bcffff1` chore: bump version to 7.1.19
  - SA 版本：无需更新（本次无 SA 相关修改）
  - 推送：`git push -u origin dev` ✅

- [2026-03-30 01:49] **同步 ai-base 2dd7f6a 至 dev 分支** ✅
  - 同步文件：`src/window_manager.c` (dispatch_after 版本)
  - 新 commit: `6a00185` on dev
  - 覆盖：之前的 pthread 实现 (ee1d33e)
  - 实现细节：dispatch_after 主队列重试 10 次 × 0.1s = 1 秒
  - 推送：`git push --force-with-lease origin dev` ✅

- [2026-03-30 01:40] **回滚错误的 memory-bank 提交** ✅
  - 错误：误将 AGENTS.md + memory-bank/ 提交到 dev 分支 (commit 3af6e91)
  - 修复：`git reset --hard ee1d33e` 回滚到 pthread 实现提交
  - 强制推送：`git push --force-with-lease origin dev` 移除远程错误提交
  - 结果：dev 分支仅保留代码变更，AI 工程文件仅存在于 ai-base

- [2026-03-29 22:15] **合并核心代码至 dev 分支** (commit: f54b4b1)
  - 合并内容：opacity 优化 + macOS 26 space creation
  - 排除内容：`.agents/`, `.opencode/`, `memory-bank/`, `AGENTS.md`, `docs/`, `skills-lock.json`
  - 合并文件：`src/event_loop.c`, `src/window_manager.c/h`, `src/osax/*.m/h`, `src/yabai.c`, `scripts/install.sh`, `CHANGELOG.md`

- [2026-03-29] **Opacity 逻辑优化** (commit: ee8cc48)
  - 新增 `window_manager_enforce_rule_opacity()` 专用函数
  - 添加 WHY 注释解释 macOS WindowServer alpha 重置行为
  - 简化 `window_did_receive_focus` 调用路径
  - 添加 dispatch block 生命周期安全检查
  - 构建验证通过，无警告

- [2026-03-29] **Phase 25-27: 代码和文档清理**
  - 删除 592 行调试代码
  - 删除 13 个过时文档
  - 编译成功，无警告

- [2026-03-28] **Phase 3.1: 类型错误修复**
  - 使用 display_space_for_display_uuid() 获取正确实例
  - 编译通过

- [2026-03-28] **Phase 2.7+3: 直接函数调用实现**
  - 函数指针直接调用 (BLR 寄存器，无距离限制)
  - 文件: src/osax/payload.m

---

## Blocked

- Phase 28 等待用户手动测试 (AGENTS.md R3: AI 禁止自动重启 yabai)