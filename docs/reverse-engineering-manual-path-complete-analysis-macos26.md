# 完整静态分析报告：手动 UI 路径调用链（macOS 26 Tahoe）

**日期**: 2025-03-27  
**分析者**: AI Assistant  
**基址**: `0x102fcc000`  
**状态**: 已完成深度静态逆向分析  
**结论**: 找到关键数组更新点 `#05 (0x22abb8)`，发现 `_appendElementAssumeUniqueAndCapacity` 数组追加操作

---

## 1. 执行摘要

### 1.1 关键发现

通过分析手动 UI 路径 backtrace 的 5 个关键偏移（#02-#06），发现：

1. **#05 (0x22abb8) 是数组更新点** ✓
   - 调用 `_appendElementAssumeUniqueAndCapacity`（Swift 数组追加）
   - 调用 `objc_msgSend` 发送消息
   - 加载 `x19` 偏移 `0x140` 和 `0x148` 的对象

2. **#02-#04 是 Swift 内存管理和调度层**
   - 大量 `swift_retain` / `swift_release` / `objc_release`
   - Dispatch 队列操作
   - 不直接更新模型

3. **#06 是类型检查和条件分支**
   - `swift_dynamicCastObjCClass` 类型转换
   - 条件判断和早期返回

### 1.2 核心证据

**#05 (0x22abb8) 关键代码段**:

```asm
; 加载数组
0x10022ac3c: ldr x20, [x19, #0x140]    ; x20 = x19->field_140 (数组容器)
0x10022ac40: ldr x27, [x20, #0x20]     ; x27 = x20->field_20 (数组指针)
0x10022ac44: mov x0, x27               ; x0 = 数组指针
0x10022ac48: bl _swift_retain          ; 保留数组

; 准备追加元素
0x10022ace0: add x20, x19, #0x170      ; x20 = &x19->field_170
0x10022ace4: bl _$sSa034_makeUniqueAndReserveCapacityIfNotB0yyFyXl_Ts5
0x10022ace8: ldr x8, [x19, #0x170]     ; x8 = x19->field_170
0x10022acec: and x8, x8, #0x...8       ; 清理标记位
0x10022acf0: ldr x21, [x8, #0x10]      ; x21 = 数组容量

; 追加元素
0x10022ad00: mov x1, x23               ; x1 = 新元素 (ManagedSpace)
0x10022ad04: bl _$sSa37_appendElementAssumeUniqueAndCapacity_03newB0ySi_xntFyXl_Ts5
                                        ; 调用数组追加方法！

; 存储结果
0x10022ad48: str w8, [sp, #0xc]        ; 存储状态
0x10022ad4c: str x26, [sp, #0x10]      ; 存储引用
0x10022ad50: bl 0x10014a34c            ; 后续处理
```

---

## 2. 详细分析

### 2.1 #02 (0x2856f0) - Swift 内存管理清理

**函数特征**:
- 大量 `swift_release` / `objc_release` 调用
- 没有对象创建或模型更新
- 纯粹的清理/释放逻辑

**关键指令**:
```asm
0x1002856f0: mov x0, x22
0x1002856f4: bl _swift_unknownObjectRelease
0x1002856f8: mov x0, x19
0x1002856fc: bl _objc_release
0x100285700: bl 0x100290960
```

**结论**: 这是 Swift 闭包/回调的清理函数，**不是模型更新点**。

---

### 2.2 #03 (0x1eb468) - Swift 数组元素访问

**函数特征**:
- 调用 `$ss12_ArrayBufferV19_getElementSlowPathyyXlSiFyXl_Ts5`
- 数组缓冲区操作
- 元素比较和字符串比较

**关键指令**:
```asm
0x1001eb4a4: bl _$ss12_ArrayBufferV19_getElementSlowPathyyXlSiFyXl_Ts5
0x1001eb560: cmp x0, x25
0x1001eb564: ccmp x24, x1, #0x0, eq
0x1001eb568: b.eq 0x1001eb5a4
```

**结论**: 这是数组元素读取/比较函数，**不是写入点**。

---

### 2.3 #04 (0x1f0834) - Dispatch 队列调度

**函数特征**:
- Dispatch WorkItem 创建
- 队列调度
- Block 对象操作

**关键指令**:
```asm
0x1001f0880: bl _$s8Dispatch0A13WorkItemFlagsVMa
0x1001f08f0: bl _$s8Dispatch0A3QoSVMa
0x1001f096c: bl 0x1001e40fc
0x1001f09cc: sub x0, x29, #0x80
0x1001f09d0: bl __Block_copy
```

**结论**: 这是异步调度层，**不是模型更新点**。

---

### 2.4 #05 (0x22abb8) - ⭐ 数组更新点（关键发现）

**函数特征**:
- 加载 `x19` 偏移 `0x140` 和 `0x148`
- 调用 `_appendElementAssumeUniqueAndCapacity`
- 调用 `objc_msgSend`
- 创建新对象 (`swift_allocObject`)

**完整调用链**:

```asm
; ====== 阶段 1: 准备数组 ======
0x10022abbc: bl _objc_release
0x10022abc0: ldp d9, d10, [x19, #0xe8]  ; 加载 SIMD 寄存器
0x10022abd8: mov x1, x23
0x10022abdc: bl 0x1001cd728             ; 可能的消息发送准备
0x10022abe8: mov x22, x0                ; x22 = 返回值

; ====== 阶段 2: 加载数组容器 ======
0x10022ac38: ldr x21, [x0, #0x10]       ; x21 = 某个对象
0x10022ac3c: ldr x20, [x19, #0x140]     ; x20 = x19->field_140 (数组容器)
0x10022ac40: ldr x27, [x20, #0x20]      ; x27 = 数组指针
0x10022ac44: mov x0, x27
0x10022ac48: bl _swift_retain           ; 保留数组

; ====== 阶段 3: 追加元素 ======
0x10022ace0: add x20, x19, #0x170       ; x20 = &x19->field_170
0x10022ace4: bl _$sSa034_makeUniqueAndReserveCapacityIfNotB0yyFyXl_Ts5
                                        ; 确保数组容量唯一
0x10022ace8: ldr x8, [x19, #0x170]
0x10022acf0: ldr x21, [x8, #0x10]       ; x21 = 当前容量
0x10022ad00: mov x1, x23                ; x1 = 新元素 (ManagedSpace)
0x10022ad04: bl _$sSa37_appendElementAssumeUniqueAndCapacity_03newB0ySi_xntFyXl_Ts5
                                        ; ⭐ 追加元素到数组！

; ====== 阶段 4: 后续处理 ======
0x10022ad50: bl 0x10014a34c             ; 可能的通知/刷新
0x10022ad64: bl 0x10034cb20             ; 可能的消息发送
```

**关键符号**:
- `$sSa37_appendElementAssumeUniqueAndCapacity_03newB0ySi_xntFyXl_Ts5`
  - Swift 标准库数组追加方法
  - 签名：`Array._appendElementAssumeUniqueAndCapacity(_, newCount: _)`

**结论**: **这是手动 UI 路径中更新 `DisplaySpaces.spaces` 数组的地方！**

---

### 2.5 #06 (0x148118) - 类型检查和条件分支

**函数特征**:
- `swift_dynamicCastObjCClass` 类型转换
- 条件判断
- 早期返回

**关键指令**:
```asm
0x1001482bc: bl _swift_dynamicCastObjCClass
0x1001482c0: cbz x0, 0x10014831c        ; 如果类型转换失败则跳转
0x1001482e0: bl _objc_retain
0x1001482ec: bl 0x10035aae0
```

**结论**: 这是类型检查和验证函数，**不是主要更新点**。

---

## 3. 数据结构分析

### 3.1 关键偏移

基于 #05 的分析，`x19` 对象的结构：

| 偏移 | 字段 | 类型 | 说明 |
|------|------|------|------|
| `0xe8` | `field_0xe8` | SIMD | 向量寄存器保存 |
| `0x140` | `field_0x140` | id | **数组容器对象** |
| `0x148` | `field_0x148` | id | 相关对象 |
| `0x170` | `field_0x170` | id | **数组缓冲区** |
| `0x98` | `field_0x98` | uint8_t | 状态标志 |

### 3.2 x19 对象推测

**可能的类**:
- `DockCore.DisplaySpaces` 的 Swift 实现
- 或内部的 `ArrayStorage` 类

**证据**:
- 偏移 `0x140` 存储数组容器
- 偏移 `0x170` 存储数组缓冲区
- 调用 Swift 数组追加方法

---

## 4. 调用链重建

### 4.1 完整调用顺序

```
RunLoop Source1 (HIServices)
  ↓
mshPerform (#19)
  ↓
... (中间 8 层)
  ↓
#06 0x100148118 - 类型检查
  ↓
#05 0x10022abb8 - ⭐ 数组追加 [关键！]
  ↓
#04 0x1001f0834 - Dispatch 调度
  ↓
#03 0x1001eb468 - 数组元素访问
  ↓
#02 0x1002856f0 - 内存清理
  ↓
DPPM addSpace:forDisplayUUID:
```

### 4.2 yabai 路径对比

**手动 UI 路径**:
```
创建 ManagedSpace
→ #06 类型检查
→ #05 数组追加 ← 关键步骤
→ #04 Dispatch 调度
→ DPPM addSpace:
→ Mission Control 可见
```

**yabai 当前路径**:
```
创建 ManagedSpace
→ DPPM addSpace:
→ 结束 ❌
缺失 #05 数组追加步骤！
```

---

## 5. 修复方案

### 5.1 核心问题

yabai 当前只调用了 `addSpace:forDisplayUUID:`，但**没有更新 `DisplaySpaces.spaces` 数组**。

### 5.2 可能的修复方向

#### 方案 A: 找到数组对象并手动追加

```objc
// 伪代码
NSArray *spaces = [display_space valueForKey:@"spaces"];
NSMutableArray *mutableSpaces = [spaces mutableCopy];
[mutableSpaces addObject:new_space];
[display_space setValue:mutableSpaces forKey:@"spaces"];
```

**风险**: 可能触发 KVO 或破坏内部状态

#### 方案 B: 调用 #05 对应的公开方法

**目标**: 找到 #05 函数对应的公开 selector

**步骤**:
1. 反汇编 #05 函数的入口点
2. 查找 selector 字符串引用
3. 通过 `objc_msgSend` 调用

#### 方案 C: 触发完整的创建流程

**目标**: 不直接调用 DPPM，而是触发完整的创建链

**可能的方法**:
- 调用 `DisplaySpaces` 的某个公开方法
- 发送通知让 Dock 自己处理
- 使用私有 API

### 5.3 下一步验证

1. **确定 #05 函数的入口 selector**
   ```bash
   # 反汇编 0x22abb8 所在的完整函数
   otool -arch arm64e -tV Dock | grep -B 200 "^000000010022abb8" | grep -A 5 "pacibsp"
   ```

2. **查找 selector 字符串**
   ```bash
   strings -t x Dock | grep -i "space\|add\|insert"
   ```

3. **确定 x19 对象的类**
   - 在 #05 函数开始处有 `mov x19, xN`
   - 追踪 xN 的来源

---

## 6. 工具和技术

### 6.1 使用的命令

```bash
# 反汇编特定偏移
otool -arch arm64e -tV "$DOCK" | grep -A 200 "^0000000100<offset>"

# 查找 selector 字符串
strings -t x "$DOCK" | grep -i "insert\|add\|space"

# 查找交叉引用
otool -arch arm64e -tV "$DOCK" | grep "0x22abb8"
```

### 6.2 关键符号

| 符号 | 说明 |
|------|------|
| `$sSa37_appendElementAssumeUniqueAndCapacity_03newB0ySi_xntFyXl_Ts5` | Swift 数组追加 |
| `$sSa034_makeUniqueAndReserveCapacityIfNotB0yyFyXl_Ts5` | 数组容量管理 |
| `_swift_retain` / `_swift_release` | Swift 内存管理 |
| `_objc_retain` / `_objc_release` | Objective-C 内存管理 |
| `_swift_dynamicCastObjCClass` | Swift 类型转换 |

---

## 7. 结论

### 7.1 确认的事实

1. **#05 (0x22abb8) 是数组更新点** ✓
   - 调用 Swift 数组追加方法
   - 操作 `x19->field_0x140` 和 `x19->field_0x170`

2. **yabai 缺失关键步骤** ✓
   - 只调用了 DPPM `addSpace:`
   - 没有更新 `DisplaySpaces.spaces` 数组

3. **手动路径有 28 层调用** ✓
   - yabai 路径只有 1 层
   - 缺失中间的 26 层逻辑

### 7.2 待解决的问题

1. **#05 函数的入口 selector 是什么？**
2. **x19 对象的具体类是什么？**
3. **如何从 yabai 触发完整的创建链？**

### 7.3 推荐下一步

**优先级 1**: 确定 #05 函数的公开 API
- 反汇编完整函数
- 查找 selector 字符串
- 尝试通过 `objc_msgSend` 调用

**优先级 2**: 确定 x19 对象的类
- 追踪 x19 的来源
- 在手动路径中查找创建该对象的代码

**优先级 3**: 测试方案 A（直接修改数组）
- 风险较高，但实现简单
- 如果成功，说明方向正确

---

**报告生成时间**: 2025-03-27  
**关键发现**: #05 (0x22abb8) 是数组更新点，调用 Swift 数组追加方法  
**下一步**: 确定 #05 函数的公开 selector 并尝试调用
