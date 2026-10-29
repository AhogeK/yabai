# Progress Archive - 2026-09

> 冷数据归档（R12）。仅供回溯，不再更新。

### Phase 39: macOS 27 (26A428) SA 修复 ✅ (2026-09-15)
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
