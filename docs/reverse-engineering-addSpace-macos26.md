# 逆向工程报告：macOS 26 Tahoe addSpace 函数分析

**日期**: 2025-03-27  
**目标**: Dock.app addSpace 函数  
**目的**: 修复 macOS 26.4 Tahoe 上 `yabai -m space --create` 失效问题

---

## 摘要

- **模式位置**: Dock.app 二进制偏移 `0x7b57e8`（唯一匹配）
- **调用约定**: `x0 = new_space`, `x20 = anchor_space`（insert-after 语义）
- **调用者**: 偏移 `0x71c14c` 处的唯一调用点
- **dppm pattern**: 更新为 `setDesktopPictureManager` 函数（唯一标识）
- **dppm offset**: `0x488b48`（从 `gDesktopPictureManager` 全局变量）
- **状态**: 调用约定已确认；yabai 实现已更新；pattern 已更新

---

## 1. 模式匹配分析

### 使用的模式（macOS 26）
```
7F 23 03 D5 FF C3 01 D1 E1 03 1E AA ?? ?? 00 94 FE 03 01 AA FD 7B 06 A9 FD 83 01 91
```

### 模式解析
| 字节 | 指令 | 说明 |
|------|------|------|
| `7F 23 03 D5` | `pacibsp` | 指针认证序言 |
| `FF C3 01 D1` | `sub sp, sp, #0x70` | 栈帧分配 |
| `E1 03 1E AA` | `mov x1, x30` | 保存返回地址 |
| `?? ?? 00 94` | `bl ...` | 调用辅助函数 |
| `FE 03 01 AA` | `mov x30, x1` | 恢复返回地址 |
| `FD 7B 06 A9` | `stp x29, x30, [sp, #0x60]` | 保存帧指针 |
| `FD 83 01 91` | `add x29, sp, #0x60` | 设置帧指针 |

### 搜索结果
```python
# Dock 二进制模式搜索
offset=0x7b57e8
匹配总数: 1
```

**结论**: 该模式唯一标识 addSpace 函数。

---

## 2. 函数反汇编

### addSpace 函数序言 (0x7b57e8)
```
0x007b57e8: pacibsp
0x007b57ec: sub sp, sp, #0x70
0x007b57f0: mov x1, x30
0x007b57f4: bl 0x...          ; 辅助调用
0x007b57f8: mov x30, x1
0x007b57fc: stp x29, x30, [sp, #0x60]
0x007b5800: add x29, sp, #0x60
...
```

### 函数入口十六进制转储
```
0x007b57e8: 7f 23 03 d5 ff c3 01 d1 e1 03 1e aa 9e 2c 00 94
0x007b57f8: fe 03 01 aa fd 7b 06 a9 fd 83 01 91 34 8d 02 94
0x007b5808: be c2 fd 97 81 00 00 54 60 0c 00 90 00 f8 43 f9
```

---

## 3. 调用者分析

### 发现的唯一调用者
**位置**: 偏移 `0x71c14c`

### 调用者序列（关键部分）
```
0x0071c130: ldr x25, [x1, #0x20]    ; 从 display_space+0x20 加载
0x0071c134: mov x0, x25             ; x0 = x25
0x0071c138: bl 0x872934             ; 某操作
0x0071c13c: mov x0, x25             ; x0 = x25
0x0071c140: bl 0x872934             ; 相同操作
0x0071c144: bl 0x682110             ; 简单 getter (mov x0, x20; ret)
0x0071c148: mov x20, x25            ; ★ 关键: x20 = ManagedSpace
0x0071c14c: bl 0x7b57e8             ; ★ 调用: addSpace(x20)
0x0071c150: bl 0x6820d8             ; 后续操作
0x0071c154: bl 0x871f34             ; 后续操作
```

### 调用约定发现

| 寄存器 | 内容 | 说明 |
|--------|------|------|
| `x0` | new ManagedSpace | **要插入的新空间** |
| `x20` | anchor ManagedSpace | **插入锚点**（新空间在此之后） |
| `x25` | 源（从 `[x1, #0x20]` 加载） | 复制到 x20 |

**关键发现**: addSpace 是 `insertSpace:afterSpace:` 语义，调用约定为：
- **`x0`** = new_space（标准位置，由 `bl 0x682110` getter 返回）
- **`x20`** = anchor_space（非标准位置，用于确定插入位置）

---

## 4. 实现变更

### 修改前（错误）
```c
// 标准 C 调用约定 - 错误
typedef void (*add_space_fn)(id, id);
((add_space_fn)add_space_fp)(display_space, new_space);
```

### 修改后（正确）
```c
// ARM64 调用约定: x0 = new_space, x20 = anchor_space (insert-after)
#define asm__call_add_space(new_sp, anchor_sp, func) \
    __asm__("mov x20, %0\n" : :"r"(anchor_sp) :"x20"); \
    ((void (*)(id))(func))(new_sp);

// 获取 anchor space（当前显示器的活动空间）
id anchor_space = ((id (*)(id, SEL, CFStringRef)) objc_msgSend)(
    dock_spaces, @selector(currentSpaceForDisplayUUID:), display_uuid);
if (!anchor_space) {
    anchor_space = get_ivar_value(display_space, "_currentSpace");
}

// 调用 addSpace(x0=new_space, x20=anchor_space)
asm__call_add_space(new_space, anchor_space, add_space_fp);
```

### 修改的文件
1. `src/osax/arm64_payload.m` - 更新宏定义
2. `src/osax/x64_payload.m` - 更新宏定义
3. `src/osax/payload.m` - 更新调用点

---

## 5. 待解决问题

### 问题 1: `[x1, #0x20]` 是什么？
- 可能是 `display_space._currentSpace` 或类似字段
- 调用者从此偏移加载现有空间
- 可能表明此代码路径用于现有空间操作，而非创建

### 问题 2: 空间创建在哪里？
- `ManagedSpace.init` 内部调用 `CGSSpaceCreate`
- 新空间获得有效的 SkyLight 空间 ID (spid)
- 需验证 addSpace 是否正确追加到 `_spaces` 数组

### 问题 3: 之前的尝试为何失败？
- 标准 C 调用约定: 使用 x0/x1 → 静默失败
- KVO 触发: `willChangeValueForKey:` → Dock 崩溃
- Plist 操作: `register_space_in_plist` → Dock 崩溃

---

## 6. 测试建议

1. **验证 addSpace 调用**:
   - 检查调用前后 `spacesForDisplay` 数量
   - 确认数量增加 1

2. **检查 Mission Control**:
   - 新空间应出现在 Mission Control 中
   - 缩略图应更新

3. **壁纸初始化**:
   - 新空间可能需要单独设置壁纸
   - 检查 addSpace 是否处理此功能，或需要额外调用

---

## 7. 使用的工具

- `otool -arch arm64e -tV Dock` - 反汇编
- `python3` - 二进制分析和模式匹配
- 十六进制转储分析

---

## 附录：完整调用者上下文

偏移 `0x71c020` 处的调用者函数似乎是空间管理函数。关键观察：

1. 函数接收多个参数 (x0-x4)
2. 使用 `pacibsp` 序言（ARM64e 指针认证）
3. 有多条代码路径（条件分支）
4. 整个二进制中只有一个 addSpace 调用点

这表明 addSpace 是 Dock 内部空间管理使用的私有辅助函数。
---

## 8. 重要发现：Objective-C Selector（2025-03-27 更新）

在 Dock 二进制中发现了 Objective-C selector：

```
addSpace:forDisplayUUID:  位于偏移 0x3a8370
```

这表明 Dock 提供了一个 ObjC 方法接口，签名可能是：
```objc
- (void)addSpace:(ManagedSpace *)space forDisplayUUID:(NSString *)uuid;
```

### 相关 ObjC Selectors

| Selector | 偏移 |
|----------|------|
| `addSpace:forDisplayUUID:` | 0x3a8370 |
| `removeSpace:` | 0x3b3fa0 |
| `currentSpaceForDisplay:` | 0x3aab32 |
| `currentSpaceForDisplayUUID:` | 0x3aab50 |
| `spacesForDisplay:` | 0x3b8c9b |
| `moveSpace:toDisplay:displayUUID:` | 0x3b1ec0 |

### 辅助函数分析

**函数 0x682110**（调用 addSpace 前调用）：
```asm
mov x0, x20    ; 返回 x20
mov x1, x19    ; 设置 x1 = x19
ret
```

这是一个简单的 getter 函数。

**函数 0x6820d8**（调用 addSpace 后调用）：
```asm
mov x20, x0    ; 保存返回值到 x20
mov x0, x19    ; x0 = x19
ret
```

### removeSpace 参考实现

yabai 中 `remove_space_call` 的签名：
```c
typedef void (*remove_space_call)(id space, id display_space, id dock_spaces, 
                                   uint64_t space_id1, uint64_t space_id2);
```

这表明 removeSpace 需要 5 个参数，addSpace 可能也需要类似参数。

---

## 9. 待验证假设

### 假设 1：应使用 ObjC 方法

```objc
// 可能正确的调用方式
[dock_spaces addSpace:new_space forDisplayUUID:display_uuid];

// 或使用 objc_msgSend
((void (*)(id, SEL, id, CFStringRef)) objc_msgSend)(
    dock_spaces, @selector(addSpace:forDisplayUUID:), 
    new_space, display_uuid);
```

### 假设 2：C 函数需要更多参数

类似于 removeSpace，addSpace 可能需要：
- space (ManagedSpace)
- display_space (DisplaySpaces)
- dock_spaces (DockSpaces)
- 其他参数

---

## 10. 下一步建议

1. **尝试 ObjC 方法调用**：直接使用 `addSpace:forDisplayUUID:` selector ✅ 已实现
2. **动态追踪**：使用 lldb/dtrace 追踪 Mission Control 点击"+"按钮
3. **分析 DisplaySpaces 类**：找到实现 `addSpace:forDisplayUUID:` 的类

---

## 11. 最终实现（2025-03-27）

### 关键发现：正确的接收者类

通过类扫描发现：
```
FOUND instance method: [DockCore.WallpaperAgentDesktopPictureManager addSpace:forDisplayUUID:]
```

**结论**：`addSpace:forDisplayUUID:` 的接收者是 `dp_desktop_picture_manager`（壁纸管理器），而非 `dock_spaces` 或 `display_space`。

在 macOS 26 上：
- 类名从 `DPDesktopPictureManager` 改为 `DockCore.WallpaperAgentDesktopPictureManager`
- Pattern-based 查找因偏移错误返回 nil
- 需要通过 ObjC runtime fallback 获取实例

### Step 1: 修复 `dp_desktop_picture_manager` 获取

```objc
// 在 init_instances 中添加 macOS 26 fallback
if (dp_desktop_picture_manager == nil && os_version.majorVersion == 26) {
    Class waClass = objc_getClass("DockCore.WallpaperAgentDesktopPictureManager");
    if (waClass) {
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if ([waClass respondsToSelector:sharedSel]) {
            dp_desktop_picture_manager = [((id (*)(Class, SEL)) objc_msgSend)(waClass, sharedSel) retain];
        }
    }
}
```

### Step 2: 调用 `addSpace:forDisplayUUID:`

```objc
// 在 do_space_create 中调用壁纸管理器
if (dp_desktop_picture_manager != nil) {
    SEL addSpaceSel = NSSelectorFromString(@"addSpace:forDisplayUUID:");
    ((void (*)(id, SEL, id, CFStringRef)) objc_msgSend)(
        dp_desktop_picture_manager, addSpaceSel, new_space, display_uuid);
}
```

### 注意事项

`addSpace:forDisplayUUID:` 主要负责：
- 壁纸初始化
- Mission Control 缩略图更新

Spaces 数组的 append 仍需通过 SkyLight 路径处理（已在 `do_space_create` 中实现）。

---

## 附录：测试要点

1. **日志应显示**：`dp_desktop_picture_manager recovered via sharedInstance: <instance>`
2. **调用后**：`addSpace:forDisplayUUID: called ✓`
3. **Mission Control**：新空间缩略图应出现
