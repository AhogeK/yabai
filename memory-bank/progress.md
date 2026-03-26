# Progress - yabai

## In Progress

- [2026-03-26 19:55] macOS 26.4 Space Creation Fix - 等待用户测试
  - 诊断发现 arm64 不使用 tagged bit
  - 利用现有 buffer 预留容量追加元素
  - 问题：tagged pointer 方案导致 Dock 崩溃

## Completed

- [2026-03-26 19:55] 诊断 Swift Array ABI
  - 发现 arm64 直接存 buffer 指针，不使用 tagged bit
  - 发现 capacity=17，有足够预留空间
  - Files: src/osax/payload.m:620-690

- [2026-03-26 19:52] 利用现有 buffer 预留容量方案
  - 不分配新 buffer，直接在预留空间追加
  - 避免分配新内存导致的 isa/refCounts 问题
  - Files: src/osax/payload.m:620-690

- [2026-03-26 19:45] tagged pointer 方案（失败）
  - 尝试 `tagged = (NSArray*) | 0x1`
  - 结果：Mission Control 打开时 Dock 崩溃
  - 原因：arm64 不使用 tagged bit

- [2026-03-26 19:30] Swift Array buffer 直接操作方案
  - 放弃 addSpace 函数调用（不可变 Swift Array）
  - 直接操作 DisplaySpaces offset=56 的 buffer 指针
  - Files: src/osax/payload.m:581-710

- [2026-03-26 19:09] 简化 do_space_create 函数
  - 移除手动操作 Swift Array buffer 的代码
  - 恢复 `asm__call_add_space(new_space, add_space_fp)` 调用
  - Files: src/osax/payload.m:581-620

- [2026-03-26] macOS 26.4 addSpace 逆向分析
  - 确认 addSpace 函数签名变化
  - x21 = ManagedSpace 参数
  - x20 从全局变量加载（不是参数）
  - 移除 pattern 末尾的 `F3 03`

- [2026-03-26] macOS 26.4 Tahoe Space Creation Fix - 初步
  - Updated addSpace byte pattern in arm64_payload.m (30→32 bytes)
  - Build passes: `make clean && make`

- [2025-03-25] AI Engineering Infrastructure Setup
  - Created AGENTS.md (139 lines) - behavioral constraints, red lines
  - Created memory-bank/ (5 files) - project memory persistence
  - Created .opencode/commands/ (2 files) - /boot and /save commands

## Backlog

_(No backlog items yet)_

## Blocked

_(No blocked items)_