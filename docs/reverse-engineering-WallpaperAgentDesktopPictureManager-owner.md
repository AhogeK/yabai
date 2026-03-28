# 逆向分析报告：WallpaperAgentDesktopPictureManager Owner 查找

**日期**: 2025-03-27  
**目标**: 找到 `DockCore.WallpaperAgentDesktopPictureManager` 实例的持有者 (owner)  
**目的**: 正确获取实例以调用 `addSpace:forDisplayUUID:` 方法

---

## 摘要

**核心问题**: `WallpaperAgentDesktopPictureManager` 是一个普通 Swift 类（0 个类方法），不是单例。需要通过静态分析找到持有它实例的 owner 对象。

**关键发现**:
1. 全局变量 `gDesktopPictureManager` 存在于 Dock 二进制
2. `setDesktopPictureManager` 函数负责设置该全局变量
3. `Wallpaper.Manager` 是独立的 Swift 类，与 `WallpaperAgentDesktopPictureManager` 分离

---

## 1. 类结构分析

### WallpaperAgentDesktopPictureManager 类

**Swift mangled name**: `_TtC8DockCore35WallpaperAgentDesktopPictureManager`

**实例方法列表** (15 个):
```
-init
-addSpace:forDisplayUUID:
-addFullscreenSpace:forDisplayUUID:
-removeSpace:
-spaceBecameFirst:onDisplay:
-displayReconfiguration
-desktopWindowForSpace:andDisplay:
-miniLayerForSpace:andDisplay:
-moveSpace:toDisplay:displayUUID:
-layerForSpace:andDisplay:
-createDesktopProxyForFSSpace:onSpace:onDisplay:
-desktopPictureDictionaryForDisplay:andSpace:
-setDesktopPictureDictionary:forDisplay:andSpace:onBehalfOfProcess:
-coordinatedDistributedNotification:
-.cxx_destruct
```

**类方法**: 0 个（不是单例）

### Ivar 布局 (从 otool 分析)

```
offset  8: windows                      (NSMutableArray)
offset 16: loginTransition              (Bool)
offset 24: wallpaperManager             (id - 指向 Wallpaper.Manager)
offset 32: remoteDesktopPictureConnectionListener
offset 40: sessionAgent
offset 48: forceHideDockAssertion
```

---

## 2. 全局变量分析

### gDesktopPictureManager

**字符串位置** (Dock 二进制):
```
0x390dfc: gDesktopPictureManager
0x8ca3d5: gDesktopPictureManager (重复)
```

**相关字符串**:
```
0x390dc8: setDesktopPictureManager
0x8ca3a1: setDesktopPictureManager (重复)
0x390447: DPDesktopPictureManager.m (源文件名)
```

### setDesktopPictureManager 函数分析

**函数地址**: `0x100339e90` (从 otool 输出推断)

**关键汇编** (简化):
```asm
0x100339e90: pacibsp
0x100339e94: stp x29, x30, [sp, #-0x10]!
...
0x100339e9c: adrp x0, 97          ; 加载 "setDesktopPictureManager" 字符串
0x100339ea0: add x0, x0, #0x3a1
0x100339ea4: adrp x1, 97          ; 加载 "DPDesktopPictureManager.m" 字符串
0x100339ea8: add x1, x1, #0x3ba
0x100339eac: adrp x3, 97          ; 加载 "!gDesktopPictureManager" 字符串
0x100339eb0: add x3, x3, #0x3d4
0x100339eb4: mov w2, #0x22        ; 行号 34 (?)
0x100339eb8: bl ___assert_rtn     ; 断言检查

0x100339ebc: adrp x0, 335         ; 加载全局变量地址
0x100339ec0: add x0, x0, #0xb48   ; gDesktopPictureManager 的实际存储位置
0x100339ec4: adrp x1, 222
0x100339ec8: add x1, x1, #0x2b0
0x100339ecc: b _dispatch_once     ; 一次性初始化

0x100339ed0: pacibsp
0x100339ed4: stp x20, x19, [sp, #-0x20]!
...
0x100339ee0: cbz x0, 0x100339efc  ; 如果 x0 为 0 则跳转
0x100339ee4: mov x19, x0          ; x19 = 现有实例
0x100339ee8: adrp x8, 310
0x100339eec: ldrsw x8, [x8, #0xebc]
0x100339ef0: ldr x9, [x0, x8]     ; 从旧实例读取某个 ivar
0x100339ef4: cmp x1, x9           ; 比较新值
0x100339ef8: b.ne 0x100339f08     ; 不同则更新

0x100339efc: ldp x29, x30, [sp, #0x10]
0x100339f00: ldp x20, x19, [sp], #0x20
0x100339f04: retab

0x100339f08: str x1, [x19, x8]    ; 存储新值到旧实例的 ivar
0x100339f0c: adrp x8, 310
0x100339f10: ldrsw x8, [x8, #0xec8]
0x100339f14: ldr x0, [x19, x8]    ; 读取另一个 ivar
0x100339f18: bl 0x100347ea0       ; 调用某个函数
0x100339f1c: mov x0, x19
0x100339f20: bl 0x10034b040       ; 调用某个函数
0x100339f24: mov x29, x29
0x100339f28: bl _objc_retainAutoreleasedReturnValue
0x100339f2c: mov x19, x0          ; 保留返回值
0x100339f30: bl 0x100351980       ; 调用某个函数
0x100339f34: mov x0, x19
0x100339f38: ldp x29, x30, [sp, #0x10]
0x100339f3c: ldp x20, x19, [sp], #0x20
0x100339f40: autibsp
0x100339f44: eor x16, x30, x30, lsl #1
0x100339f48: tbz x16, #0x3e, 0x100339f50
0x100339f4c: brk #0xc471
0x100339f50: b _objc_release
```

**函数行为分析**:
1. 断言检查 `gDesktopPictureManager` 非空
2. 使用 `dispatch_once` 确保一次性初始化
3. 比较新旧值，如果不同则更新
4. 调用多个辅助函数（可能是 KVO 通知或清理）
5. 返回保留的实例

---

## 3. 相关符号

### Wallpaper 框架引用

**nm 输出** (外部符号):
```
_$s9Wallpaper0A7ManagerC14makeFirstSpace5space7displayySS_10Foundation4UUIDVtKF
_$s9Wallpaper0A7ManagerC15makeMainDisplayyy10Foundation4UUIDVF
_$s9Wallpaper0A7ManagerCACycfc
_$s9Wallpaper23getLegacyDesktopPicture5space7displaySDys11AnyHashableVypGSS_SStKF
_$s9Wallpaper23setLegacyDesktopPicture_5space7display17onBehalfOfProcessySDys11AnyHashableVypG_S2SSo13audit_token_taSgtKF
```

**解释**:
- `Wallpaper.Manager` 是独立类
- 有 `makeFirstSpace`、`makeMainDisplay` 等方法
- 与 `WallpaperAgentDesktopPictureManager` 分离

### 关键字符串

```
AnalyticsDesktopPictureKind
DesktopWallpaperWindow
WallpaperAgentDesktopPictureManager
WallpaperLayerContainer
DesktopPictureWindow
DPDesktopPictureManager.m
!gDesktopPictureManager
com.apple.dock.desktoppicture
com.apple.wallpaper
com.apple.dock.remotedesktoppicture
```

---

## 4. 全局变量地址计算

### 从 otool 输出推断

`setDesktopPictureManager` 函数中:
```
0x100339ebc: adrp x0, 335 ; 0x100488000
0x100339ec0: add x0, x0, #0xb48
```

**计算**:
- 基地址：`0x100488000`
- 偏移：`0xb48`
- **全局变量地址**: `0x100488b48`

### 验证方法

在 yabai 代码中直接读取:
```objc
// 假设 baseaddr 是 Dock 的基地址
uint64_t global_addr = 0x100488b48;  // 需要运行时验证
id *globalPtr = (id *)(void *)global_addr;
id instance = *globalPtr;
```

**注意**: 由于 ASLR，实际地址需要加上 slide 值。

---

## 5. 获取实例的正确方式

### 方案 A: 从全局变量读取 (推荐)

```objc
// 使用 dlsym 查找全局符号
void *handle = dlopen(NULL, RTLD_NOW);
id *globalPtr = (id *)dlsym(handle, "gDesktopPictureManager");
if (globalPtr) {
    dp_desktop_picture_manager = [*globalPtr retain];
}
dlclose(handle);
```

### 方案 B: 从 dock_spaces ivar 查找

如果全局符号不可访问，扫描 `dock_spaces` 的 ivar:
```objc
Class dsClass = object_getClass(dock_spaces);
unsigned int ivarCount = 0;
Ivar *ivars = class_copyIvarList(dsClass, &ivarCount);
for (unsigned int i = 0; i < ivarCount; i++) {
    const char *ivarName = ivar_getName(ivars[i]);
    ptrdiff_t offset = ivar_getOffset(ivars[i]);
    id value = *(id *)((uint8_t *)(__bridge void *)dock_spaces + offset);
    if ([value isKindOfClass:waClass]) {
        dp_desktop_picture_manager = [value retain];
        break;
    }
}
free(ivars);
```

### 方案 C: 直接从固定偏移读取

```objc
// 需要验证 ASLR slide
uint64_t slide = _dyld_get_image_vmaddr_slide(0);
uint64_t global_addr = 0x100488b48 + slide;
id instance = *(id *)(void *)global_addr;
```

---

## 6. 下一步验证

1. **验证全局符号可访问性**:
   - 在 yabai 中尝试 `dlsym(handle, "gDesktopPictureManager")`
   - 如果返回 NULL，符号未导出

2. **验证 ivar 扫描**:
   - 扫描 `dock_spaces` 的所有 ivar
   - 查找类型为 `WallpaperAgentDesktopPictureManager` 的对象

3. **验证固定偏移**:
   - 计算 ASLR slide
   - 读取 `0x100488b48 + slide` 的值
   - 检查是否为有效对象指针

---

## 7. 结论

**最可能的获取路径**:

```
Dock 初始化
    ↓
调用 setDesktopPictureManager(instance)
    ↓
存储到 gDesktopPictureManager 全局变量 (0x100488b48)
    ↓
WallpaperAgentDesktopPictureManager 持有 wallpaperManager (Wallpaper.Manager 实例)
    ↓
调用 [dp_desktop_picture_manager addSpace:forDisplayUUID:]
```

**推荐实现**: 使用 `dlsym` 查找全局符号，失败时回退到 ivar 扫描。

---

## 附录：完整字符串列表

```
AnalyticsDesktopPictureKind
DesktopWallpaperWindow
WallpaperAgentDesktopPictureManager
WallpaperLayerContainer
DesktopPictureWindow
Remove desktop wallpaper window: <%x>
Update desktop wallpaper window: <%x: origin: [x: %f, y: %f], size: [width: %f, height: %f, context colorSpace: %s]>
Created desktop wallpaper window: <%x: space: '%s', display: '%s', size: [width: %f, height: %f], context colorSpace: %s, needsBackdrop: %{bool}d>
Creating desktop wallpaper window for named space without backdrop
BEGIN: Wallpaper initialization
displayReconfiguration: Removing wallpaper window for display: %{public}s
END: Wallpaper initialization
desktoppicturechanged
setDesktopPictureManager
DPDesktopPictureManager.m
!gDesktopPictureManager
com.apple.dock.desktoppicture
live-wallpaper-in-show-desktop
DockCore.DesktopWallpaperWindow
enable-wallpaper-flattening
com.apple.wallpaper
com.apple.dock.remotedesktoppicture
WallpaperLayer space=
Acquire WallpaperDisplayAssertion
com.apple.wallpaper.agent
live-wallpaper-in-mission-control
Unable to update main display for wallpaper agent.
live-wallpaper-in-app-expose
com.apple.ec.DesktopPicture.usage
com.apple.ec.DesktopPicture.databaseFailure
com.apple.ec.DesktopPicture.failure
.desktopPicture
_TtC8DockCore22DesktopWallpaperWindow
_TtC8DockCore35WallpaperAgentDesktopPictureManager
_TtCC8DockCore35WallpaperAgentDesktopPictureManagerP33_565896611C050AD0423D03CFF7C040F622ForceHideDockAssertion
DPDesktopPictureManagerProtocol
_TtC8DockCore23WallpaperLayerContainer
_desktopPictureChanged:
_needToUpdateDesktopPicture
desktopPicture
desktopPictureDictionaryForDisplay:andSpace:
desktopPictureProxy
desktopPictureWindows
liveWallpaperAssertion
remoteDesktopPictureConnectionListener
setDesktopPictureDictionary:forDisplay:andSpace:onBehalfOfProcess:
useWallpaperTinting
wallpaperLayerContainer
wallpaperManager
```