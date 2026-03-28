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

### Phase 28: 重新测试 ⏳ PENDING

- [ ] `sudo make install`
- [ ] `yabai --restart-service`
- [ ] `yabai -m space --create` 测试
- [ ] 验证 Mission Control 中出现新 space

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