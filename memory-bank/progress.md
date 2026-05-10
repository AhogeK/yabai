# Progress - yabai

## Current Phase: 上游 30 commits 同步完成 (2026-04-26)

---

## Phase History

### Phase 35: 上游 30 commits 全量同步 ✅ (2026-04-26)
- **范围**: `7c4c5ba` → `f51e4b5` (30 commits)
- **方式**: 逐个 cherry-pick，版本冲突用我们的版本解决
- **版本**: 7.1.21 → 7.1.25
- **构建**: ✅ 成功，无警告
- **报告**: `docs/upstream-sync-report-2026-04-26.md`

### Phase 34: 上游 O_CLOEXEC 锁文件修复 + 版本 bump ✅ (2026-04-13)
- **来源**: upstream commit `5e21351` (asmvik/yabai, 2026-04-06), issue #2775
- **问题**: lock fd 无 `O_CLOEXEC` → 子进程继承 → yabai 重启时锁僵死无法启动
- **修复**: `open(g_lock_file, O_CREAT | O_WRONLY | O_CLOEXEC, 0600)`
- **版本文件更新**:
  - `src/yabai.c`: PATCH 20 → 21
  - `scripts/install.sh`: VERSION "7.1.20" → "7.1.21"
  - `CHANGELOG.md`: 添加 7.1.21 条目
  - `src/osax/common.h`: SA 版本保持 2.1.27 (无 SA 变更)
- **构建**: ✅ 成功，无警告

---

## Key Findings

### 架构分离 (macOS 26)

```
"+" 按钮 → 0x1f07d8 (Swift 方法, x0=display_id, x20=Spaces self)
          → 内部: ManagedSpace alloc + 数组追加 + CGS 注册
          → DPPM addSpace:forDisplayUUID: (壁纸)
```

### 关键发现

- macOS 26 Dock 已用 Swift 重写 (`DockCore` 框架)
- Swift self 放在 callee-saved 寄存器 (x20)，非 ObjC 的 x0
- `0x1f07d8` 是 Swift 方法，需要 Spaces singleton 作为 self
- 编译器优化: 延迟栈帧分配、add+ldr 融合
- IOKit 在 Dock 沙箱下不可用，需用 CoreGraphics SPI

---

## Completed (已归档)

### Phase 33: DPPM Scanner False Positive Fix ✅
- 控制流指纹 (cbnz+str) + 数据流校验消除 false positive
- offset `0x4880d0` 验证通过

### Phase 32: DPPM Dynamic Address Decoding ✅
- `decode_adrp_ldr_pair()`: LDR offset bits 10-21, scale by 8
- `find_dppm_singleton_instructions()`: 5 指令序言锚点 + behavioral fingerprint

### Phase 31: 多显示器支持 ✅
- `display_id_for_uuid()` 使用 `CGDisplayCreateUUIDFromDisplayID`
- 移除 IOKit 依赖 (沙箱不可用)

### Phase 30: Space 创建历史性成功 ✅
- `space_create_entry returned` 首次成功
- Dock 不崩溃，Mission Control 显示新 space

### Phase 29: 宏修复 ✅
- 原子 `asm volatile` + `blr` + retain/release + 完整 clobber

### Phase 27.1: 地址重复计算修复 ✅

### Phase 25-27: 代码/文档清理 ✅

### Phase 1-3: 分析与实现 ✅

### 其他已完成
- 版本同步 7.1.20/7.1.21 到所有分支
- 签名清理 (所有分支)
- Opacity 优化
- Makefile deploy 修复
- 逆向工程文档体系建立 (13 份文档)

---

## Memory Bank 状态

| 文件 | 行数 | 限制 | 状态 |
|------|------|------|------|
| activeContext.md | ~100 | 150 | ✅ |
| progress.md | ~80 | 100 | ✅ |
| systemPatterns.md | ~60 | 80 | ✅ |
| techContext.md | ~60 | 80 | ✅ |
| projectbrief.md | ~25 | 50 | ✅ |
- [2026-05-10] Phase 36: Sync upstream #2788 (7 commits), version 7.1.26
