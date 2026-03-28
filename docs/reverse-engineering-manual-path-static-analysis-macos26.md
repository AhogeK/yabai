# 静态分析报告：手动 UI 路径调用链（macOS 26 Tahoe）

**日期**: 2025-03-27  
**基址**: `0x102fcc000`  
**目标**: 找到手动 UI 创建桌面时，谁负责更新 `DisplaySpaces.spaces` 数组

---

## 1. 调用栈摘要

### 1.1 完整 Backtrace（28 层）

```
#00 dump_backtrace_symbols_filtered (yabai)
#01 traced_dppm_add_space (yabai)
#02 0x1032516f0  ← DPPM 内部调用
#03 0x1031b7468
#04 0x1031bc834
#05 0x1031f6bb8
#06 0x103114118
#07 0x1031f88b8
#08 0x1031f8c6c
#09 0x1031f89ac
#10 0x103059f40
#11 0x102ffbdf0
#12 0x102ffb3f4
#13 0x10305f4c8
#14 0x1031d6718
#15 0x1032b161c
#16 0x1032b1684
#17 0x103086e00
#18 0x103086b50
#19 mshPerform (HIServices) ← RunLoop Source1 回调
#20-#27 CoreFoundation RunLoop
```

### 1.2 关键偏移计算

**运行时基址**: `0x102fcc000`  
**静态基址**: `0x100000000`  
**ASLR Slide**: `0x2fcc000`

| 帧号 | 运行时地址 | 静态 VM 地址 | 文件偏移 | 说明 |
|------|-----------|-----------|----------|------|
| #02 | `0x1032516f0` | `0x1002856f0` | `0x2856f0` | DPPM 内部直接调用者 |
| #03 | `0x1031b7468` | `0x1001eb468` | `0x1eb468` | 上层调用者 |
| #04 | `0x1031bc834` | `0x1001f0834` | `0x1f0834` | 上层调用者 |
| #05 | `0x1031f6bb8` | `0x10022abb8` | `0x22abb8` | 上层调用者 |
| #06 | `0x103114118` | `0x100148118` | `0x148118` | 可能的模型更新点 |

---

## 2. 静态反汇编命令

### 2.1 反汇编 #02（最优先）

```bash
DOCK=/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock

# 反汇编 0x2856f0 处的函数（50 条指令）
otool -arch arm64e -tV "$DOCK" | grep -A 100 "^00000001002856f0"
```

**期望看到**:
- 函数序言（pacibsp / stp x29,x30）
- 对 `ManagedSpace` 的消息发送
- 对 `DisplaySpaces` 的访问
- 在调用 DPPM `addSpace:` 前后的操作

### 2.2 反汇编 #03-#06

```bash
# 反汇编 #03
otool -arch arm64e -tV "$DOCK" | grep -A 80 "^00000001001eb468"

# 反汇编 #04
otool -arch arm64e -tV "$DOCK" | grep -A 80 "^00000001001f0834"

# 反汇编 #05
otool -arch arm64e -tV "$DOCK" | grep -A 80 "^000000010022abb8"

# 反汇编 #06
otool -arch arm64e -tV "$DOCK" | grep -A 80 "^0000000100148118"
```

---

## 3. 分析重点

### 3.1 寻找的模式

**理想调用顺序**:
```
创建 ManagedSpace
→ 更新 DisplaySpaces.spaces 数组
→ 调用 DPPM addSpace:forDisplayUUID:
→ 刷新 UI
```

**yabai 当前路径**:
```
创建 ManagedSpace
→ 调用 DPPM addSpace:forDisplayUUID:
→ 结束 ❌
```

**缺失的步骤**: 更新 `DisplaySpaces.spaces` 数组

### 3.2 关键指令模式

#### 对 `DisplaySpaces` 的访问

```asm
; 读取 _displaySpaces ivar
ldr x0, [xN, #0x...]  ; x0 = dock_spaces
ldr x0, [x0, #0x...]  ; x0 = _displaySpaces
```

#### 对 `spaces` 数组的更新

```asm
; 调用 insertObject:atIndex: 或 addObject:
ldr x0, [xN, #0x...]  ; x0 = spaces array
mov x1, xM            ; x1 = new_space
bl _objc_msgSend      ; [spaces insertObject:new_space atIndex:...]
```

#### Selector 字符串引用

```asm
; 加载 selector
adrp x1, PAGE
add  x1, x1, #OFFSET  ; x1 = @"insertObject:atIndex:"
```

### 3.3 需要查找的 Selector

| Selector | 说明 |
|----------|------|
| `insertObject:atIndex:` | 插入对象到数组 |
| `addObject:` | 添加对象到数组 |
| `setSpaces:` | 设置 spaces 数组 |
| `setCurrentSpace:` | 设置当前空间 |
| `spaces` | 读取 spaces 数组 |
| `currentSpace` | 读取当前空间 |

---

## 4. 函数边界识别

### 4.1 函数序言特征

**ARM64e 函数序言**:
```asm
pacibsp                    ; 指针认证
stp x29, x30, [sp, #-0x10]!  ; 保存帧指针和返回地址
mov x29, sp                ; 设置帧指针
```

**或**:
```asm
stp x29, x30, [sp, #-0x10]!
mov x29, sp
sub sp, sp, #0x...         ; 分配栈空间
```

### 4.2 函数尾声特征

```asm
ldp x29, x30, [sp], #0x10  ; 恢复帧指针和返回地址
retab                      ; 返回并认证
```

**或**:
```asm
add sp, sp, #0x...         ; 释放栈空间
ldp x29, x30, [sp], #0x10
retab
```

---

## 5. 分析步骤

### 5.1 第一步：反汇编 #02（0x2856f0）

**目标**: 确认这是 DPPM 的内部方法还是上层调用者

**查找**:
1. 函数序言位置
2. 对 `addSpace:forDisplayUUID:` 的调用位置
3. 调用前的操作（是否在更新数组？）
4. 调用后的操作（是否有刷新 UI？）

**预期**:
- 如果 #02 是 DPPM 内部方法，继续分析 #03
- 如果 #02 已经是上层调用者，重点分析

### 5.2 第二步：反汇编 #03（0x1eb468）

**目标**: 找到第一个非 DPPM 的调用者

**查找**:
1. 是否访问 `DisplaySpaces` 对象
2. 是否调用数组更新方法
3. 与 #02 的调用关系

### 5.3 第三步：交叉引用分析

```bash
# 查找谁调用了 0x2856f0
otool -arch arm64e -tV "$DOCK" | grep "0x2856f0\|0x2856f"
```

---

## 6. 假设与验证

### 假设 A: 数组更新在 #02-#06 之间

**证据**:
- 手动路径有 28 层调用栈
- yabai 路径只有 1 层（直接调用 DPPM）
- 差异就在中间的 26 层

**验证方法**:
1. 反汇编 #02-#06
2. 查找数组更新指令
3. 确认 selector 字符串

### 假设 B: 数组更新在 DPPM 调用之前

**证据**:
- 手动 UI 创建后 `spid=208` 立即出现在数组中
- yabai create 后 `spid=209` 不在数组中

**验证方法**:
1. 在 #02-#06 中查找 `addSpace:` 调用
2. 确认调用 `addSpace:` 之前是否有数组更新

### 假设 C: 数组更新由另一个并行路径完成

**证据**:
- RunLoop Source1 回调（#19 `mshPerform`）
- 可能是异步事件处理

**验证方法**:
1. 分析 #19-#18 的调用链
2. 查找并行线程/队列操作

---

## 7. 工具使用指南

### 7.1 otool 反汇编

```bash
# 基本反汇编
otool -arch arm64e -tV "$DOCK" | grep -A 50 "^0000000100<offset>"

# 查找 selector 引用
otool -arch arm64e -tV "$DOCK" | grep -B 5 -A 5 "insertObject"
```

### 7.2 Ghidra/Hopper 分析

**导入 Dock 二进制**:
1. 打开 Ghidra/Hopper
2. 导入 `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock`
3. 选择 ARM64e 架构
4. 等待分析完成

**跳转到偏移**:
- Ghidra: 按 `G` 键，输入 `0x1002856f0`
- Hopper: 菜单栏 Go → Go to Address

**查看交叉引用**:
- 右键点击函数/指令 → Show Xrefs

### 7.3 字符串分析

```bash
# 查找所有 selector 字符串
strings -t x "$DOCK" | grep -i "insert\|add\|space\|display"

# 查找特定 selector
strings -t x "$DOCK" | grep "insertObject:atIndex:"
```

---

## 8. 预期发现

### 8.1 最可能的情况

**手动 UI 路径**:
```
RunLoop Source1 (HIServices)
  → mshPerform (#19)
  → ... (#18-#10)
  → 更新 DisplaySpaces.spaces (#06-#03)
  → 调用 DPPM addSpace: (#02)
  → traced_dppm_add_space (yabai #01)
```

**yabai 路径**:
```
yabai -m space --create
  → CGSSpaceCreate
  → traced_dppm_add_space (yabai)
  → DPPM addSpace:
  → 结束 ❌
```

**缺失的步骤**: 更新 `DisplaySpaces.spaces`

### 8.2 修复方案

找到手动路径中更新数组的方法后：

```objc
// 在 addSpace:forDisplayUUID: 之前调用
SEL insertSel = NSSelectorFromString(@"insertObject:atIndex:");
NSArray *spaces = [display_space valueForKey:@"spaces"];
NSUInteger count = [spaces count];
[display_space insertValue:new_space atIndex:count inPropertyWithKey:@"spaces"];
```

---

## 9. 下一步行动

### 9.1 立即执行

1. **禁用 `displayReconfiguration`** ✓
2. **反汇编 #02（0x2856f0）**
3. **反汇编 #03（0x1eb468）**
4. **记录每个函数的 selector 调用**

### 9.2 分析输出

对于每个反汇编结果：
1. 识别函数边界（序言/尾声）
2. 标记所有 `bl _objc_msgSend` 调用
3. 查找对应的 selector 字符串
4. 记录对 `DisplaySpaces` / `ManagedSpace` 的访问

### 9.3 成功标准

当找到以下模式时说明成功：
```asm
; 在调用 addSpace: 之前
ldr x0, [xN, #0x...]  ; x0 = spaces array
mov x1, xM            ; x1 = new_space
bl _objc_msgSend      ; [spaces insertObject:new_space...]
```

---

**报告生成时间**: 2025-03-27  
**下一步**: 静态反汇编 #02-#06 偏移
