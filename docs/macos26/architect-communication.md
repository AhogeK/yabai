# macOS 26 Space Creation - 架构师沟通文档

**版本**: v0.1.0  
**日期**: 2026-03-29  
**状态**: 代码已实现，待测试验证  
**提交**: `06ee433`

---

## 📋 目录

1. [当前状态](#当前状态)
2. [已尝试方案](#已尝试方案)
3. [未解决问题](#未解决问题)
4. [技术细节](#技术细节)
5. [下一步计划](#下一步计划)
6. [与架构师讨论点](#与架构师讨论点)

---

## 当前状态

### 代码实现 ✅

| 组件 | 状态 | 说明 |
|------|------|------|
| `asm__call_space_create_tahoe` 宏 | ✅ 完成 | Swift 调用约定实现 |
| `get_space_create_entry_offset()` | ✅ 完成 | 返回 0x1f07d8 偏移 |
| `do_space_create()` macOS 26 路径 | ✅ 完成 | 直接调用 0x1f07d8 |
| 代码清理 | ✅ 完成 | 删除调试代码和未使用函数 |
| 文档清理 | ✅ 完成 | 仅保留核心 LLDB 分析文档 |

### 测试结果 ⏳

- **编译**: ✅ 成功，无警告
- **功能测试**: ⏳ 待测试
- **LLDB 验证**: ⏳ 待执行

---

## 已尝试方案

### 方案 1: 直接调用 0x1f07d8（当前实现）✅

**LLDB 发现** (`lldb-analysis2.md`):
```
Frame 1 (___lldb_unnamed_symbol_10022ab54):
<+80>:  ldr    w23, [x20, #0x38]  ; w23 = 1 (display_id)
<+88>:  mov    x20, x0            ; x20 = Spaces singleton
<+92>:  mov    x0, x23            ; x0 = display_id
<+96>:  bl     0x1f07d8           ; 调用！
```

**实现**:
```c
#define asm__call_space_create_tahoe(display_id, spaces_self, func) \
    __asm__("mov w0, %w0\n""mov x20, %1\n" \
        : :"r"((int32_t)(display_id)), "r"((uintptr_t)(spaces_self)) \
        :"w0", "x20"); \
    ((void (*)())(func))()

// 调用
id spaces_singleton = *(id *)(base_addr + slide + 0x488028);
dispatch_sync(dispatch_get_main_queue(), ^{
    asm__call_space_create_tahoe(CGMainDisplayID(), spaces_singleton, 0x1f07d8);
});
```

**问题**: 待测试验证

---

### 方案 2: ObjC 消息路径（备选）⏳

**思路**: 通过 `WallpaperAgentDesktopPictureManager.addSpace:forDisplayUUID:` 间接创建

**优点**: 
- 已验证 UI 路径可行
- 不需要处理 Swift 调用约定

**缺点**:
- 需要创建 `ManagedSpace` 对象
- 需要正确的 `displayUUID` 参数
- 可能仍然需要底层调用

**状态**: 代码已保留，待方案 1 失败后启用

---

### 方案 3: CGS API 调用（已放弃）❌

**思路**: 使用 `CGSManagedDisplayAddSpace` 等私有 API

**发现**:
```c
// probe_cgs_space_symbols() 探测结果
CGSAddManagedSpace: NULL
CGSManagedDisplayAddSpace: NULL
CGSAddSpace: NULL
CGSSpaceCreate: 0xfd6c80018982d518 (仅符号存在)
```

**结论**: macOS 26 已移除/隐藏这些符号，无法使用

---

### 方案 4: 数组直接修改（已放弃）❌

**思路**: 直接修改 `DisplaySpaces._spaces` 数组

**发现**:
- `_spaces` 是 Swift `ContiguousArray<ManagedSpace>`
- 不是 ObjC `NSArray`
- 直接修改会导致内存布局错误

**结论**: Swift 内部数据结构，无法安全修改

---

## 未解决问题

### 1. 功能验证 ⏳

**问题**: 代码已实现但未经实际测试

**风险**:
- 可能仍然崩溃
- 可能 space 创建成功但 Mission Control 不刷新
- 可能多显示器场景有问题

**计划**:
```bash
sudo make install
yabai --restart-service
yabai -m space --create
```

---

### 2. Swift 调用约定不确定性 ⚠️

**问题**: LLDB 分析显示 `x20` 是 Swift self，但：
- 不确定是否还有其他隐藏参数
- 不确定函数内部是否需要特定状态
- 不确定是否需要先分配 `ManagedSpace`

**LLDB 证据**:
```
$x0 = 0x1 (display_id, int32_t)
$x20 = Spaces singleton (Swift self)
```

**风险**: 可能缺少其他必要参数或状态

---

### 3. Mission Control 刷新 ⚠️

**问题**: 即使 space 创建成功，Mission Control 可能不刷新显示

**可能方案**:
1. 调用 `CGSManagedDisplayAddSpace` 通知 WindowServer
2. 发送 `NSWorkspaceDidActivateApplicationNotification`
3. 重启 Dock（不可取）

**状态**: 已预留 `cgs_notify_space_created()` 但未启用

---

### 4. 多显示器支持 ⏳

**问题**: 当前实现使用 `CGMainDisplayID()`，只支持主显示器

**待实现**:
```c
// 需要根据 display_uuid 找到对应的 CGDirectDisplayID
CGDirectDisplayID display_id = get_display_id_from_uuid(display_uuid);
```

**状态**: 待功能验证后再实现

---

## 技术细节

### 0x1f07d8 函数签名

**推断签名**:
```c
// Swift calling convention
// self in x20, first arg in x0
void space_create_entry(int32_t display_id);  // self = Spaces singleton
```

**证据**:
1. Frame 1 汇编显示 `bl 0x1f07d8` 前设置 `x0=1, x20=Spaces`
2. 函数入口 `pacibsp` 是标准 Swift 函数 prologue
3. 不是 ObjC 方法（没有 `self` 和 `_cmd` 寄存器传递）

---

### Spaces Singleton 位置

**全局变量偏移**: `0x488028` (文件偏移)

**运行时地址计算**:
```c
uintptr_t spaces_global_ptr = base_addr + image_slide + 0x488028;
id spaces_singleton = *(id *)spaces_global_ptr;
```

**验证**:
```
LLDB Session 1: slide=0x04374000 → 0x1047fc028
LLDB Session 2: slide=0x049a8000 → 0x104e30028
po $x20 → <Spaces: 0xcbe808480> ✅
```

---

### Swift 调用约定

**ARM64 Swift 调用约定**:
| 寄存器 | 用途 |
|--------|------|
| `x0-x7` | 参数 1-8 |
| `x20-x28` | Callee-saved (Swift self 通常在这里) |
| `x29` | Frame pointer |
| `x30` | Link register |

**当前实现**:
```c
// x0 = display_id (int32_t, 用 w0 传递)
// x20 = Spaces singleton (Swift self)
__asm__("mov w0, %w0\n""mov x20, %1\n"
    : :"r"((int32_t)(display_id)), "r"((uintptr_t)(spaces_self))
    :"w0", "x20");
```

---

## 下一步计划

### Phase 1: 功能验证 (最高优先级)

```bash
# 1. 安装
sudo make install

# 2. 重启
yabai --restart-service

# 3. 测试
yabai -m space --create

# 4. 查看日志
log show --predicate 'process == "Dock" AND message CONTAINS "yabai"' --last 2m --info
```

**预期结果**:
- ✅ Dock 不崩溃
- ✅ Mission Control 显示新 space
- ✅ 日志显示调用成功

**如果失败**:
- 收集崩溃日志
- LLDB 分析 `0x1f07d8` 入口寄存器状态
- 对比原生调用和 yabai 调用的差异

---

### Phase 2: 问题修复 (根据 Phase 1 结果)

**场景 A: 崩溃**
- LLDB 设置断点在 `0x1f07d8`
- 查看调用时的 `x0`, `x20` 值
- 对比原生调用的寄存器状态

**场景 B: 不崩溃但 space 不显示**
- 检查 `ManagedSpace` 是否正确分配
- 检查 `DisplaySpaces._spaces` 数组是否更新
- 可能需要调用 CGS 通知函数

**场景 C: 单显示器成功，多显示器失败**
- 实现 `get_display_id_from_uuid()`
- 为每个显示器调用创建逻辑

---

### Phase 3: 代码优化 (功能稳定后)

- [ ] 移除所有调试 NSLog
- [ ] 添加错误处理
- [ ] 添加单元测试
- [ ] 更新 README.md
- [ ] 添加 macOS 26 支持说明

---

## 与架构师讨论点

### 1. Swift 调用约定的正确性 ⚠️

**问题**: 当前实现基于 LLDB 推断的 Swift 调用约定，但没有官方文档支持

**讨论点**:
- 是否有其他方式验证调用约定？
- 是否需要反编译整个函数确认参数？
- 是否有 macOS 26 的 Swift ABI 文档？

---

### 2. Spaces Singleton 的获取方式 ⚠️

**问题**: 当前使用硬编码偏移 `0x488028`

**风险**: 
- macOS 小版本更新可能改变偏移
- 不同硬件配置可能有不同偏移

**讨论点**:
- 是否需要动态扫描全局变量？
- 是否有更可靠的方式获取 Spaces 实例？
- 是否应该通过 ObjC runtime 获取？

---

### 3. Mission Control 刷新机制 ⚠️

**问题**: 即使 space 创建成功，Mission Control 可能不刷新

**讨论点**:
- 是否需要调用 `CGSManagedDisplayAddSpace`？
- 是否需要发送通知？
- 是否需要触发 Dock 重绘？

---

### 4. 多显示器架构设计 ⚠️

**问题**: 当前实现只支持主显示器

**讨论点**:
- 是否应该为每个显示器创建独立的 `DisplaySpaces` 调用？
- 是否需要维护显示器到 `DisplaySpaces` 的映射？
- 如何处理显示器热插拔？

---

### 5. 长期维护策略 ⚠️

**问题**: macOS 26 仍在测试阶段，API 可能变化

**讨论点**:
- 是否应该添加版本检测？
- 是否应该提供 fallback 机制？
- 是否应该等待 macOS 26 正式发布后再完善？

---

## 附录：相关文件

### 核心实现
- `src/osax/arm64_payload.m`: `asm__call_space_create_tahoe` 宏
- `src/osax/payload.m`: `do_space_create()` macOS 26 路径

### 分析文档
- `docs/macos26/lldb-analysis.md`: 第一次 LLDB 会话（完整分析）
- `docs/macos26/lldb-analysis2.md`: 第二次 LLDB 会话（寄存器值）

### Memory Bank
- `memory-bank/activeContext.md`: 当前工作状态
- `memory-bank/progress.md`: 详细进度记录

---

## 联系

**问题反馈**: 请基于具体 LLDB 输出和日志分析  
**测试请求**: 请在 macOS 26 Tahoe 上测试 `yabai -m space --create`  
**架构建议**: 特别是 Swift 调用约定和多显示器架构设计

---

**最后更新**: 2026-03-29  
**提交**: `06ee433`  
**状态**: 待测试验证
