# 逆向工程报告：gDesktopPictureManager 调用链深度分析（macOS 26 Tahoe）

**日期**: 2025-03-27  
**状态**: 已完成深度静态逆向分析  
**结论**: `0x488b48` 和 `0x488b58` 都不是实例槽位，实例存储位置需要通过运行时动态追踪

---

## 执行摘要

### 核心发现

1. **`0x100488b48` 不是实例槽位** - 可能是 `dispatch_once_t` token 或其他状态标志
2. **`0x100488b58` 初始值为 `0x100000003be0a0`** - 这是指针，不是 token
3. **`0x10046f000` 段存储元数据** - 字符串引用，不是实例指针
4. **`0x100339ed0` 是 setter 函数** - 接受 `(self, value)` 参数，写入 `0x10046f000` 段的偏移
5. **`0x1004172b0` 和 `0x100417330` 不是标准 block** - invoke 指针为 0

### 当前结论

**`WallpaperAgentDesktopPictureManager` 实例不存储在全局数据段**。可能存储在：
- 某个 owner 对象的 ivar 中
- 使用 Associated Objects 机制
- 运行时动态创建并缓存

---

## 1. 函数结构分析

### 1.1 三个相关函数

| 地址 | 名称 | 功能 |
|------|------|------|
| `0x100339e90` | 函数 A | 断言检查 + dispatch_once(`0x100488b48`) |
| `0x100339ed0` | 函数 B | Setter: `-[SomeClass setField:value:]` |
| `0x10033a134` | 函数 C | dispatch_once(`0x100488b58`) |

### 1.2 函数 B (0x100339ed0) 详细分析

```asm
; 函数签名：unknown_type setField(x0=self, x1=value)
0x100339ed0: pacibsp
0x100339ed4: stp     x20, x19, [sp, #-0x20]!
0x100339ed8: stp     x29, x30, [sp, #0x10]
0x100339edc: add     x29, sp, #0x10
0x100339ee0: cbz     x0, 0x100339efc    ; if (self == nil) return
0x100339ee4: mov     x19, x0            ; self -> x19
0x100339ee8: adrp    x8, 310             ; 0x10046f000
0x100339eec: ldrsw   x8, [x8, #0xebc]   ; offset = global[0xebc]
0x100339ef0: ldr     x9, [x0, x8]       ; old_value = self[offset]
0x100339ef4: cmp     x1, x9             ; if (value != old_value)
0x100339ef8: b.ne    0x100339f08        ;   set_new_value()
0x100339efc: ldp     x29, x30, [sp, #0x10]
0x100339f00: ldp     x20, x19, [sp], #0x20
0x100339f04: retab
0x100339f08: str     x1, [x19, x8]      ; self[offset] = value
```

**关键点**:
- `x0` = self 对象指针
- `x1` = 新值（可能是指针或整数）
- 从 `0x10046f000 + 0xebc` 读取偏移
- 写入 `self[offset]`

### 1.3 函数 C (0x10033a134) 分析

```asm
0x10033a134: adrp    x0, 334             ; 0x100488000
0x10033a138: add     x0, x0, #0xb58     ; x0 = 0x100488b58 (token/pointer)
0x10033a13c: adrp    x1, 221             ; 0x100417000
0x10033a140: add     x1, x1, #0x330     ; x1 = 0x100417330 (block/data)
0x10033a144: bl      _dispatch_once
```

**关键发现**:
- `0x100488b58` 的初始值是 `0x100000003be0a0`（不是 0）
- 这不是 `dispatch_once_t` token（token 初始值应为 0）
- 可能是某种指针或状态字

---

## 2. 调用者分析

### 2.1 函数 B 的调用点 (0x1000b1104)

```asm
0x1000b10f8: bl      0x10034ff40        ; some_function()
0x1000b10fc: sxtw    x1, w0             ; x1 = sign_extend(return_value)
0x1000b1100: ldr     x0, [sp, #0x30]    ; x0 = [sp+0x30] (object pointer)
0x1000b1104: bl      0x100339ed0        ; setField(x0, x1)
```

**分析**:
- `x1` 是符号扩展的整数（`sxtw`）
- `x0` 从栈上加载（对象指针）
- 这说明 `0x100339ed0` 接受整数参数，不是对象指针

### 2.2 函数 A 的调用点 (0x10011cdd4)

```asm
0x10011cdd4: bl 0x100339e90
```

**上下文**: 在某个初始化函数中被调用。

---

## 3. 0x10046f000 段分析

### 3.1 静态内容

| 偏移 | 地址 | 值 | 含义 |
|------|------|-----|------|
| `0xeb4` | `0x46feb4` | `0x003937dc00100000` | 元数据 |
| `0xeb8` | `0x46feb8` | `0x00100000003937dc` | → `0x3937dc`: `/tmp/MCSpace...` |
| `0xebc` | `0x46febc` | `0x003b215000100000` | → `0x3b2150`: `r:` |
| `0xecc` | `0x46fecc` | `0x003a4dbb00100000` | → `0x3a4dbb`: `essTree:forPath:withOptions:` |
| `0xec8` | `0x46fec8` | `0x00100000003a8ab6` | → `0x3a8ab6`: `Binding` |

### 3.2 结论

**`0x10046f000` 段存储的是元数据**：
- 字符串常量
- 方法选择器
- 文件路径

**不是实例指针槽位**。

---

## 4. dispatch_once block 分析

### 4.1 Block 1 (0x1004172b0)

```
isa:     0x0000000000000400 (无效)
flags:   0x0000000000000010
invoke:  0x0000000000000000 (NULL!)
```

**结论**: 不是标准的 Objective-C block。

### 4.2 Block 2 (0x100417330)

```
数据：a1 ab 2b 00 00 00 10 00 ...
invoke: 0x0 (NULL!)
```

**结论**: 同样不是标准 block。

---

## 5. 为什么找不到实例

### 5.1 可能的原因

**假设 A: 实例存储在 ivar 中**
```objc
@interface DockController : NSObject {
    WallpaperAgentDesktopPictureManager *_dppm;  // 存储在 ivar
}
@end
```

**假设 B: 使用 Associated Objects**
```objc
objc_setAssociatedObject(owner, @selector(dppm), instance, ...);
```

**假设 C: 延迟初始化**
```objc
static WallpaperAgentDesktopPictureManager *gInstance = nil;
// 第一次访问时才创建
```

### 5.2 运行时验证的必要性

静态分析无法确定：
- 实例在运行时的存储位置
- 谁拥有 `WallpaperAgentDesktopPictureManager` 实例
- 实例何时被创建

**需要动态追踪**。

---

## 6. 下一步行动计划

### 6.1 高优先级（动态追踪）

1. **遍历所有 Objective-C 对象**:
   ```c
   // 在 do_space_create 时
   int count = objc_getClassList(NULL, 0);
   Class *classes = malloc(count * sizeof(Class));
   objc_getClassList(classes, count);
   
   for (int i = 0; i < count; i++) {
       if (strstr(class_getName(classes[i]), "Wallpaper") != NULL) {
           // 找到相关类，遍历其实例
       }
   }
   ```

2. **查找 `addSpace:forDisplayUUID:` 的 receiver**:
   ```c
   // 在调用 addSpace:forDisplayUUID: 前打印 receiver
   debug_log(@"addSpace receiver=%p class=%s", 
             (void *)receiver, 
             class_getName(object_getClass(receiver)));
   ```

3. **添加多个全局段探针**:
   ```c
   // 读取 0x10046f000 段的不同偏移
   id probe1 = *(id *)(baseaddr + 0x46feb8);
   id probe2 = *(id *)(baseaddr + 0x46fec8);
   debug_log(@"global[0xeb8]=%p global[0xec8]=%p", probe1, probe2);
   ```

### 6.2 中优先级（静态分析）

4. **反汇编 `0x10034ff40` 函数**（调用函数 B 之前的函数）:
   - 确定返回值类型
   - 追踪数据流

5. **查找 `0x100488b58` 的所有引用**:
   - 确定这个指针的用途
   - 是否有写入操作

### 6.3 备选方案

如果动态追踪失败：
- 使用 Frida 插桩追踪 `objc_alloc` / `init` 调用
- 或寻找其他获取壁纸管理器实例的途径

---

## 7. 验证命令

### A. 动态遍历对象

```c
// 添加到 do_space_create
int count = objc_getClassList(NULL, 0);
Class *classes = malloc(count * sizeof(Class));
objc_getClassList(classes, count);

for (int i = 0; i < count; i++) {
    const char *name = class_getName(classes[i]);
    if (strstr(name, "Wallpaper") != NULL || 
        strstr(name, "DesktopPicture") != NULL) {
        debug_log(@"Found class: %s", name);
    }
}
free(classes);
```

### B. 追踪 receiver

```c
// 在调用 addSpace:forDisplayUUID: 前
debug_log(@"Calling addSpace: receiver=%p", (void *)receiver);
debug_log(@"Receiver class: %s", class_getName(object_getClass(receiver)));
```

---

## 8. 结论

### 8.1 确认的事实

1. **`0x488b48` 和 `0x488b58` 都不是实例槽位**
2. **`0x10046f000` 段存储元数据**，不是实例指针
3. **`0x100339ed0` 是 setter 函数**，接受整数参数
4. **`0x1004172b0` 和 `0x100417330` 不是标准 block**

### 8.2 待解决的问题

1. **实例存储在哪里？** - 需要动态遍历对象
2. **谁拥有实例？** - 需要追踪 `addSpace:forDisplayUUID:` 的 receiver
3. **实例何时创建？** - 需要动态追踪 alloc/init

### 8.3 成功标准

当以下日志出现时说明找到正确位置：
```
Found class: DockCore.WallpaperAgentDesktopPictureManager
Instance at: 0x...
addSpace receiver: 0x... class=DockCore.WallpaperAgentDesktopPictureManager
```

---

**报告生成时间**: 2025-03-27  
**下一步**: 动态追踪实例创建和存储位置
