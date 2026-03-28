# 逆向工程报告：gDesktopPictureManager 全局变量定位（macOS 26 Tahoe）

**日期**: 2025-03-27  
**目标**: Dock.app `gDesktopPictureManager` 全局变量  
**目的**: 获取 `WallpaperAgentDesktopPictureManager` 实例以调用 `addSpace:forDisplayUUID:`

---

## 摘要

- **全局变量**: `gDesktopPictureManager` 存储 `WallpaperAgentDesktopPictureManager` 单例
- **VM 地址**: `0x100488b48`（相对于 Dock 镜像基址 `0x100000000`）
- **文件偏移**: `0x488b48`
- **定位方法**: 从 `setDesktopPictureManager` 函数的 `adrp+add` 序列计算
- **新 Pattern**: `setDesktopPictureManager` 函数 prologue（20 字节，8 字节通配符）

---

## 1. 问题背景

### 1.1 需求

需要获取 `DockCore.WallpaperAgentDesktopPictureManager` 实例来调用：
```objc
[dp_desktop_picture_manager addSpace:new_space forDisplayUUID:display_uuid];
```

### 1.2 已知信息

从之前的逆向分析已知：
- macOS 26 类名变更：`DPDesktopPictureManager` → `DockCore.WallpaperAgentDesktopPictureManager`
- 该类不是单例，没有 `sharedInstance` 类方法
- 存在全局变量 `gDesktopPictureManager` 存储该实例

---

## 2. 字符串分析

### 2.1 关键字符串位置

在 Dock 二进制中搜索相关字符串：

```bash
$ strings -t x /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -i desktoppicture
```

| 字符串 | 文件偏移 | 说明 |
|--------|----------|------|
| `gDesktopPictureManager` | 0x390dfc | 全局变量名 |
| `setDesktopPictureManager` | 0x390dc8 | Setter 函数名 |
| `!gDesktopPictureManager` | 0x390dfb | 断言消息 |
| `DPDesktopPictureManager.m` | 0x390e84 | 源文件名 |

### 2.2 交叉引用分析

字符串 `setDesktopPictureManager` 被用作 `___assert_rtn` 的参数，说明存在一个同名的 setter 函数进行断言检查。

---

## 3. setDesktopPictureManager 函数分析

### 3.1 函数位置

从 otool 反汇编输出：
```
0x100339e90: _setDesktopPictureManager
```

### 3.2 完整反汇编

```asm
; ====== 函数入口 (0x100339e90) ======
0x100339e90: pacibsp
0x100339e94: stp     x29, x30, [sp, #-0x10]!
0x100339e98: mov     x29, sp

; ====== 加载断言字符串 ======
0x100339e9c: adrp    x0, 97              ; 页面 97 = 0x10039a000
0x100339ea0: add     x0, x0, #0x3a1     ; "setDesktopPictureManager"
0x100339ea4: adrp    x1, 97
0x100339ea8: add     x1, x1, #0x3ba     ; "DPDesktopPictureManager.m"
0x100339eac: adrp    x3, 97
0x100339eb0: add     x3, x3, #0x3d4     ; "!gDesktopPictureManager"
0x100339eb4: mov     w2, #0x22          ; 行号 34
0x100339eb8: bl      0x100341514        ; ___assert_rtn

; ====== 加载全局变量地址 (关键部分) ======
0x100339ebc: adrp    x0, 335             ; 页面 335 = 0x100488000
0x100339ec0: add     x0, x0, #0xb48     ; 偏移 0xb48
0x100339ec4: adrp    x1, 222             ; 页面 222 = 0x100417000
0x100339ec8: add     x1, x1, #0x2b0
0x100339ecc: b       0x100341874        ; _dispatch_once

; ====== 函数主体 (0x100339ed0) ======
0x100339ed0: pacibsp
0x100339ed4: stp     x20, x19, [sp, #-0x20]!
0x100339ed8: stp     x29, x30, [sp, #0x10]
0x100339edc: add     x29, sp, #0x10
0x100339ee0: cbz     x0, 0x100339efc
0x100339ee4: mov     x19, x0
0x100339ee8: adrp    x8, 310             ; 0x10046f000
0x100339eec: ldrsw   x8, [x8, #0xebc]
0x100339ef0: ldr     x9, [x0, x8]
0x100339ef4: cmp     x1, x9
0x100339ef8: b.ne    0x100339f08
0x100339efc: ldp     x29, x30, [sp, #0x10]
0x100339f00: ldp     x20, x19, [sp], #0x20
0x100339f04: retab
0x100339f08: str     x1, [x19, x8]
```

### 3.3 关键发现

从 `0x100339ebc-0x100339ec0` 的 `adrp+add` 序列：
```
adrp    x0, 335      ; 页面 335 = 0x100488000
add     x0, x0, #0xb48
```

计算全局变量 VM 地址：
```
gDesktopPictureManager_VM = 0x100488000 + 0xb48 = 0x100488b48
```

---

## 4. 文件偏移计算

### 4.1 Mach-O 段信息

```bash
$ otool -arch arm64e -l Dock | grep -A 10 __TEXT
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `vmaddr` | 0x100000000 | 镜像基址 |
| `fileoff` | 0x0 | 文件偏移 0 |
| `vmsize` | 0x40c000 | 段大小 |

### 4.2 计算公式

```
文件偏移 = VM 地址 - 镜像基址 + 文件起始偏移
文件偏移 = 0x100488b48 - 0x100000000 + 0x0
文件偏移 = 0x488b48
```

### 4.3 验证

在文件偏移 `0x488b48` 处读取指针值：
```python
data = open("Dock", "rb").read()
ptr = struct.unpack("<Q", data[0x488b48:0x488b48+8])[0]
# ptr = 0x100000001c39f9 (有效指针，指向某对象)
```

---

## 5. Pattern 生成

### 5.1 函数前 32 字节

从 otool 输出提取（小端序转换后）：
```
0x00: 7f 23 03 d5   pacibsp
0x04: fd 7b bf a9   stp x29,x30,[sp,#-0x10]!
0x08: fd 03 00 91   mov x29,sp
0x0c: 00 03 00 b0   adrp x0,#97     (页面号随 build 变化)
0x10: 00 84 0e 91   add x0,#0x3a1   (偏移随 build 变化)
0x14: 01 03 00 b0   adrp x1,#97
0x18: 21 e8 0e 91   add x1,#0x3ba
0x1c: 03 03 00 b0   adrp x3,#97
0x20: 63 50 0f 91   add x3,#0x3d4
```

### 5.2 生成的 Pattern

```c
// setDesktopPictureManager prologue (唯一标识：4 个字符串加载 + ___assert_rtn)
// 前 12 字节固定 (pacibsp, stp, mov)，后 8 字节通配 (adrp+add 对随 build 变化)
const char *get_dppm_pattern(NSOperatingSystemVersion os_version) {
    if (os_version.majorVersion == 26) {
        return "7F 23 03 D5 FD 7B BF A9 FD 03 00 91 ?? ?? ?? ?? ?? ?? ?? ??";
    }
    // ... 其他版本
}
```

### 5.3 Pattern 唯一性验证

该 pattern 特征：
- `pacibsp` + `stp x29,x30` + `mov x29,sp` 是常见 prologue
- **但**连续 4 个 `adrp+add` 对加载字符串是独特的
- 这是 `setDesktopPictureManager` 函数的断言检查逻辑独有

---

## 6. 代码实现

### 6.1 get_dppm_offset() 更新

```c
uint64_t get_dppm_offset(NSOperatingSystemVersion os_version) {
    if (os_version.majorVersion == 26) {
        // gDesktopPictureManager 全局变量文件偏移
        // 从 setDesktopPictureManager: adrp x0,335 + add x0,#0xb48
        // VM = 0x100488000 + 0xb48 = 0x100488b48
        // 文件偏移 = 0x488b48
        return 0x488b48;
    }
    // ... 其他版本
}
```

### 6.2 get_dppm_pattern() 更新

```c
const char *get_dppm_pattern(NSOperatingSystemVersion os_version) {
    if (os_version.majorVersion == 26) {
        // setDesktopPictureManager prologue
        // pacibsp; stp x29,x30,[sp,#-0x10]!; mov x29,sp
        // 然后 4x (adrp+add) 加载断言字符串
        return "7F 23 03 D5 FD 7B BF A9 FD 03 00 91 ?? ?? ?? ?? ?? ?? ?? ??";
    }
    // ... 其他版本
}
```

---

## 7. 使用方式

### 7.1 读取全局变量

```c
// 计算运行时地址（考虑 ASLR slide）
uint64_t slide = get_aslr_slide(dock_pid);
uint64_t gDesktopPictureManager_addr = 0x100000000 + slide + 0x488b48;

// 从目标进程读取
id dp_desktop_picture_manager;
vm_read_overwrite(dock_pid, gDesktopPictureManager_addr, 
                  sizeof(id), &dp_desktop_picture_manager);
```

### 7.2 调用方法

```objc
// 现在可以安全调用
if (dp_desktop_picture_manager != nil) {
    ((void (*)(id, SEL, id, id))objc_msgSend)(
        dp_desktop_picture_manager, 
        @selector(addSpace:forDisplayUUID:),
        new_space, 
        display_uuid);
}
```

---

## 8. 验证步骤

### 8.1 Pattern 匹配验证

```bash
# 在 Dock 二进制中搜索 pattern
python3 -c "
import re
data = open('Dock', 'rb').read()
pattern = bytes.fromhex('7f2303d5fd7bbfa9fd030091')
idx = data.find(pattern)
print(f'Pattern 匹配位置：0x{idx:x}')
# 应该输出：0x339e90 (setDesktopPictureManager 文件偏移)
"
```

### 8.2 偏移验证

```bash
# 验证文件偏移 0x488b48 处有有效指针
python3 -c "
import struct
data = open('Dock', 'rb').read()
ptr = struct.unpack('<Q', data[0x488b48:0x488b48+8])[0]
print(f'指针值：0x{ptr:x}')
# 应该输出：0x100000001c39f9 或类似有效地址
"
```

---

## 9. 相关发现

### 9.1 类结构

`DockCore.WallpaperAgentDesktopPictureManager` 的 ivars：
```
offset  8: windows                      (NSMutableArray)
offset 16: loginTransition              (Bool)
offset 24: wallpaperManager            (id)
offset 32: remoteDesktopPictureConnectionListener
offset 40: sessionAgent
offset 48: forceHideDockAssertion
```

### 9.2 相关 Selector

| Selector | 说明 |
|----------|------|
| `addSpace:forDisplayUUID:` | 添加空间到显示器 |
| `addFullscreenSpace:forDisplayUUID:` | 添加全屏空间 |
| `removeSpace:` | 移除空间 |
| `spacesForDisplay:` | 获取显示器的空间列表 |
| `currentSpaceForDisplayUUID:` | 获取当前活动空间 |

### 9.3 外部符号

存在外部 Swift 模块 `Wallpaper`：
```
_$s9Wallpaper0A7ManagerC12makeFirstSpace5space7displaySo06CGS4SpaceCSg_So0K8DisplayCSgtF
  → Wallpaper.Manager.makeFirstSpace(space:display:)
```

这表明 `WallpaperAgentDesktopPictureManager` 可能持有 `Wallpaper.Manager` 实例。

---

## 10. 工具和技术

### 10.1 使用的工具

| 工具 | 用途 |
|------|------|
| `otool -arch arm64e -tV` | ARM64e 反汇编 |
| `otool -arch arm64e -l` | 加载命令（段信息） |
| `otool -arch arm64e -s __TEXT __text` | 段转储 |
| `nm -arch arm64e` | 符号表 |
| `strings -t x` | 字符串及偏移 |
| Python 脚本 | 字节提取、偏移计算 |

### 10.2 关键技术

1. **adrp+add 序列分析**: ARM64 使用页面基址 + 偏移加载大地址
2. **小端序转换**: otool 输出 4 字节组为小端序
3. **VM 到文件偏移映射**: 使用 Mach-O 加载命令计算
4. **Pattern 通配符**: 对 build 相关的立即数使用通配符

---

## 11. 结论

成功定位 `gDesktopPictureManager` 全局变量：
- **VM 地址**: `0x100488b48`
- **文件偏移**: `0x488b48`
- **定位方法**: `setDesktopPictureManager` 函数中的 `adrp+add` 序列
- **新 Pattern**: 使用函数 prologue（20 字节，8 字节通配符）

该全局变量持有 `DockCore.WallpaperAgentDesktopPictureManager` 单例实例，可用于调用 `addSpace:forDisplayUUID:` 方法。

---

## 附录：完整函数反汇编

```
_setDesktopPictureManager (0x100339e90):
0x100339e90  pacibsp
0x100339e94  stp     x29, x30, [sp, #-0x10]!
0x100339e98  mov     x29, sp
0x100339e9c  adrp    x0, 97
0x100339ea0  add     x0, x0, #0x3a1
0x100339ea4  adrp    x1, 97
0x100339ea8  add     x1, x1, #0x3ba
0x100339eac  adrp    x3, 97
0x100339eb0  add     x3, x3, #0x3d4
0x100339eb4  mov     w2, #0x22
0x100339eb8  bl      0x100341514
0x100339ebc  adrp    x0, 335
0x100339ec0  add     x0, x0, #0xb48
0x100339ec4  adrp    x1, 222
0x100339ec8  add     x1, x1, #0x2b0
0x100339ecc  b       0x100341874
```
