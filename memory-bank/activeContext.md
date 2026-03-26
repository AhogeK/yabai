# Active Context - yabai

## Current Work Focus

**macOS 26.4 Space Creation Bug** - 利用现有 buffer 预留容量追加元素

## Recent Changes

- [2026-03-26 19:55] - 诊断发现 arm64 不使用 tagged bit
  - Files: src/osax/payload.m:620-690
  - Finding: `raw slot value = 0x973321bc0` (末尾是 0，不是 tagged)
  - Finding: `class=_TtGCs23_ContiguousArrayStoragePs9AnyObject__$`
  - Finding: `field@16=5 field@24=17` (count=5, capacity=17)
  - Impact: tagged pointer 方案完全错误，arm64 直接存 buffer 指针

- [2026-03-26 19:52] - 利用现有 buffer 预留容量追加元素
  - Files: src/osax/payload.m:620-690
  - Change: 不分配新 buffer，直接在预留空间追加
  - Reason: 避免分配新内存导致的 isa/refCounts 问题
  - Method: `elements[old_count] = new_space; *(count_ptr) = old_count + 1;`

- [2026-03-26 19:45] - tagged pointer 方案（已废弃）
  - Files: src/osax/payload.m:620-690
  - Change: `tagged = (NSArray*) | 0x1`
  - Result: Mission Control 打开时 Dock 崩溃
  - Reason: arm64 不使用 tagged bit，Swift 读到错误指针

- [2026-03-26 19:30] - 实现 Swift Array buffer 直接操作
  - Files: src/osax/payload.m:581-710
  - Change: 放弃 addSpace 函数调用，直接操作 DisplaySpaces 的 Swift Array buffer
  - Reason: `_ContiguousArrayStorage` 是不可变的，不支持 addObject
  - Method: 读取 offset=56 的 buffer 指针，构造新 buffer，追加新元素，写回指针

## Current Diff Status

```
AGENTS.md: +35 -0 (R1/R2 强化)
memory-bank/: +83 行 (记录更新)
src/osax/payload.m: +138 -2
  - do_space_create: 利用现有 buffer 预留容量追加
  - 添加诊断日志
src/osax/arm64_payload.m: +6 -0
  - asm__call_add_space 宏（已不使用）
```

## Key Findings (From Reverse Engineering)

1. **Swift Array Buffer ABI (arm64)**:
   - slot 直接存储 `_ContiguousArrayStorage*` 指针
   - **不使用 tagged bit**（与 x86_64 不同）
   - 内存布局：`+0:isa, +8:refCounts, +16:count, +24:capacity, +32:elements`

2. **预留容量**:
   - `capacity=17`，当前只有 3-5 个 spaces
   - 可以直接在预留空间追加，不需要分配新 buffer

3. **Ghost Space 原因**:
   - 手动操作 Swift Array buffer 没有触发 Dock 内部初始化
   - 必须调用 add_space_fp 来正确注册 space

## Next Steps

1. 用户测试：`sudo make install-osax && yabai --restart-service`
2. 测试：`yabai -m space --create`
3. 检查日志：`cat /tmp/yabai-sa-debug.log`
4. 验证 Mission Control 是否崩溃