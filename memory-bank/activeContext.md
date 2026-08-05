# Active Context - yabai

## Current Work Focus

**上游同步完成: 30 commits cherry-picked (2026-04-26)**

---

## 📋 最新变更

**版本**: 7.1.25 (基于 7.1.21 + 上游 30 commits)

**上游同步范围**: `7c4c5ba` → `f51e4b5` (30 commits)

**关键变更**:
- #2780: `Space --focus` 支持 SIP 启用模式 (5 commits)
- #2781: 绕过 space 切换动画 + FFM 手势防护 (6 commits)
- #2217: FFM 窗口 ID 重置 + 菜单事件修复 (2 commits)
- #2147: 现代 macOS stub 旧函数 (1 commit)
- #2694: 自动对焦延迟调整 (2 commits)
- #2708: Intel x64 SA 修复 (2 commits)
- macOS 26.4 Intel SA 更新 (1 commit)
- 清理/文档 (3 commits)
- 版本 bump (8 commits, 使用我们的版本号)

**冲突解决**: CHANGELOG/install.sh/yabai.c 版本冲突全部用我们的版本解决

---

## ✅ 已完成的核心功能

### macOS 26 Space 创建 (Phase 1-33)
- **space_create_entry** (`0x1f07d8`): Swift 方法，调用约定 `x0=display_id, x20=Spaces singleton(self)`
- **原子调用宏**: `asm volatile` + `blr` + `objc_retain`/`objc_release` + 完整 clobber 列表
- **Spaces 单例动态定位**: DOUBLE-ANCHOR 方案 (bl→0x1f07d8 + 回溯 adrp/add)，offset `0x488028`
- **DPPM 动态定位**: 控制流指纹 (cbnz+str guard) + 数据流校验，offset `0x4880d0`，adrp+ldr 融合
- **多显示器支持**: `CGDisplayCreateUUIDFromDisplayID` (IOKit 在 Dock 沙箱下不可用)
- **测试结果**: `space_create_entry returned` ✅, Dock 不崩溃 ✅, Mission Control 显示新 space ✅

### Opacity 优化
- `window_manager_enforce_rule_opacity()` 专用函数
- rule opacity bypass active/normal 系统
- dispatch block 生命周期安全检查

### 代码/文档清理
- 删除 592 行调试代码，13 个过时文档
- 所有分支 commit message 清除 AI 署名

---

## 📚 逆向工程知识沉淀 (docs/)

### 核心发现
1. **macOS 26 Dock 已用 Swift 重写**: `DockCore` 框架，Spaces/SpacesBarWindowController 等均为 Swift 类
2. **Swift 调用约定**: self 放在 callee-saved 寄存器 (x20)，非标准 ObjC 的 x0
3. **编译器优化影响**: Xcode 16.3+ 延迟栈帧分配 (deferred stack allocation)，add+ldr 融合为单条 ldr
4. **Pattern 稳定性**: `pacibsp` (7F 23 03 D5) 是 arm64e 非叶子函数天然锚点，但栈帧大小/BL 目标随编译变化

### 逆向方法论 (my-reverse-engineering-learn.md)
- 工具链: Ghidra (主力) + LLDB (动态验证) + dsdump (ObjC/Swift 元数据) + Frida (运行时 hook)
- 定位策略: 字符串引用链 > ObjC 方法表 > stub 反向定位
- Pattern 提取: 稳定字节 (opcode/寄存器操作) vs 不稳定字节 (BL 偏移/栈帧/adrp 页地址)
- Version Tracking: 两版本 binary 对比，快速定位变化函数

### 关键文档
- `reverse-engineering-addSpace-macos26.md`: addSpace 函数分析，调用约定 `x0=new_space, x20=anchor_space` (早期发现，后被 Swift 层覆盖)
- `reverse-engineering-manual-path-complete-analysis-macos26.md`: 手动 UI 路径 28 层调用链，#05 (0x22abb8) 是数组追加点
- `reverse-engineering-gDesktopPictureManager-macos26.md`: gDesktopPictureManager 全局变量定位，VM `0x100488b48`
- `reverse-engineering-dppm-callgraph-macos26.md`: DPPM 调用链深度分析，实例不在全局数据段
- `reverse-engineering-WallpaperAgentDesktopPictureManager-owner.md`: DPPM Owner 查找，15 个实例方法，0 个类方法
- `my-reverse-report.md`: 完整技术报告，从崩溃到动态解算的完整推理链
- `debug-addSpace-lldb.md`: LLDB 调试指南
- `macos26/lldb-analysis.md`: 第一次 LLDB 会话 (完整分析)
- `macos26/lldb-analysis2.md`: 第二次 LLDB 会话 (寄存器值确认)
- `macos26/architect-communication.md`: 架构师沟通文档

---

## ⚠️ 已知设计限制 (不处理)

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字 (1秒覆盖) | Apple 未暴露相关 API，无完美解法 |
- [2026-05-10 06:30] - Sync upstream #2788 (7 commits ce798b7..02de172)
  - File: src/space_manager.c - upstream bridged window management for moving windows between spaces with SIP
  - File: src/misc/extern.h - added SLSPerformAsynchronousBridgedWindowManagementOperation function pointer
  - Version: 7.1.25 -> 7.1.26
  - Conflict resolved: space_manager.c used upstream version for #2788 SIP window move support
- [2026-06-15 16:24] - Sync upstream #2799 (add_space pattern for macOS 26.6 Apple Silicon)
  - File: src/osax/arm64_payload.m - change pattern from exact match to wildcard (48 89 FC 97 -> ?? ?? ?? 97)
  - File: src/osax/common.h - bump OSAX_VERSION from 2.1.29 to 2.1.30
  - File: CHANGELOG.md - add entry under 7.1.26 Fixed section
  - Version remains 7.1.26 (no version bump)
- [2026-08-05] Fix space creation on macOS 26.6 (build 25G72, Dock 2427.6)
  - Root cause: space_create_entry moved 0x1f07d8 -> 0x1f07d4 (4-byte shift, pacibsp now at 0x1f07d4); dock_spaces pattern (from doBindingCommand:display) 0 matches in new build
  - File: src/osax/arm64_payload.m - get_space_create_entry_offset 0x1f07d8 -> 0x1f07d4
  - File: src/osax/payload.m - add pacibsp verify +-64B scan fallback; add dock_spaces DOUBLE-ANCHOR fallback (dock_spaces == Spaces singleton 0x488028, passed as Swift self x20)
  - File: src/osax/common.h - OSAX_VERSION 2.1.30 -> 2.1.31
  - Verified static: 0x1f07d4 pacibsp, callers 0x22abb0/0x27eb0c bl->entry, backtrack -> 0x488028; DPPM 0x4880d0 unaffected
  - Build: make success (universal binary)
