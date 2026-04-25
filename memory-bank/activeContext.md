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
