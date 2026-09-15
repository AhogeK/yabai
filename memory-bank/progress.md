# Progress - yabai

## Current Phase: macOS 27 空间创建/窗口聚焦修复 ⏳ (2026-09-15)

---

## Phase History

### Phase 39: macOS 27 (26A428) SA 修复 ⏳ (2026-09-15)
- **环境**: macOS 27.0 (26A428)，Dock 2571.0.6.402，WindowManager.framework 462.0.8
- **症状**: 系统升级后 space --create / space --focus / window --focus 全部失效
- **根因 1**: `verify_os_version()` 无 27 分支 → `init_instances()` 提前 return，SA 所有功能失效
- **根因 2**: Dock 删除 Swift 空间创建入口（26.6 的 0x1f07d4），空间管理下沉到 WindowManager.framework
- **修复**:
  - 新增 27 版本门 + 全套 offset/pattern 27 分支（dppm 0x40000、remove/move 0x180000、fix_anim 0x220000）
  - set_front_window pattern 首位通配化（cbz 立即数变化）→ 唯一命中 0x192bc
  - 空间创建改走 `WindowManager.WindowManager.synchronouslyRequestCreateManagedSpace(displayUUID:)`
    （dlsym mangled 符号 + Swift ABI：x20=self，x0/x1=String，错误在 x21）
  - OSAX_VERSION 2.1.31 → 2.1.32
- **静态验证**: ✅ pattern 命中/唯一性/全局解码（Spaces=0x100409bb0，DPPM=0x100409c50）+ x86_64/arm64 编译通过
- **状态**: ✅ **已完成并端到端验证**（7.1.29；yabai `space --create` 实测 10 -> 11，Dock 无崩溃）
- **7.1.29→7.1.33 迭代（2026-09-15）**:
  - 29: dlsym 指针需 `blraaz`（PAC 崩溃修复）
  - 30/31: WindowManager admin XPC 的断言制路径（layout control → create → commit）——实测不通
  - 32: Dock 内直连 `CGSSpaceCreate` —— 返回 NULL
  - 33: 静态定位到 Dock 内部 Swift helper `0x2bb62c`（与 WindowManager.app `0x100426ab0` 逐字节同构 = "+"按钮同源）+ cid 懒加载 getter `0x2c2aa8`；改为在主线程调用该 helper（G3 XPC 降级为回退）

### Phase 38: macOS 26.6 (25G72) space creation fix ✅ (2026-08-05)
- space_create_entry 0x1f07d8 → 0x1f07d4；dock_spaces pattern 0 匹配 → DOUBLE-ANCHOR 兜底（0x488028）
- DPPM 0x4880d0 不受影响；OSAX_VERSION 2.1.29 → 2.1.30 → 2.1.31

### Phase 37: 上游 #2799 add_space pattern (2026-06-15) ✅
- macOS 26.6 Apple Silicon add_space pattern 通配化（48 89 FC 97 → ?? ?? ?? 97）

### Phase 36: 上游 #2788 同步 (2026-05-10) ✅
- 版本 7.1.26；`SLSPerformAsynchronousBridgedWindowManagementOperation`（SIP enabled 下跨 space 移动窗口）

### Phase 35: 上游 30 commits 全量同步 (2026-04-26) ✅
- `7c4c5ba` → `f51e4b5`，版本 7.1.21 → 7.1.25，报告见 `docs/upstream-sync-report-2026-04-26.md`

### Phase 1-34: macOS 26 Tahoe 空间创建从 0 到 1 ✅
- 30~33: Space 创建成功（Swift 调用约定 + 原子 asm 宏 + DPPM 动态定位 + 多显示器）
- 25~29: 地址重复计算修复 / 调试代码清理
- 早期: addSpace 调用约定、自定义 asm 宏、逆向文档体系建立

---

## Key Findings（跨版本）

- macOS 26 起 Dock 用 Swift 重写（DockCore 框架）；macOS 27 起空间/窗口管理下沉到 WindowManager.framework
- Swift 调用约定：实例方法 `self` 在 callee-saved `x20`；throwing 方法错误在 `x21`；String 是 2 word（x0/x1）
- 全局单例都在 `__DATA,__common`：可通过 "objc stub → selector → 接收者全局" 的寄存器级抽象解释做语义画像
- IOKit 在 Dock 沙箱下静默失败 → 用 CoreGraphics UUID API

## Memory Bank 状态

| 文件 | 行数 | 限制 | 状态 |
|------|------|------|------|
| activeContext.md | ~100 | 150 | ✅ |
| progress.md | ~60 | 100 | ✅ |
| systemPatterns.md | ~78 | 80 | ✅ |
| techContext.md | ~78 | 80 | ✅ |
| projectbrief.md | 22 | 50 | ✅ |
