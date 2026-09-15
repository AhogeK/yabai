# 逆向工程报告：macOS 27 (26A428) 空间创建 / 窗口聚焦修复

**日期**: 2026-09-15
**目标**: Dock.app (Dock 2571.0.6.402, macOS 27.0 build 26A428)、WindowManager.framework (462.0.8)
**目的**: 修复 macOS 27 上 `yabai -m space --create` / `space --focus` / `window --focus` 再次失效问题

---

## 0. 结论摘要

| 项目 | macOS 26.6 (旧) | macOS 27.0 (新) |
|------|----------------|----------------|
| Spaces 单例全局 | `0x488028` | `0x100409bb0`（**pattern 不变，基址仍 0x30000**） |
| DPPM 单例全局 | `0x4880d0` | `0x100409c50`（pattern 不变，**搜索基址 0x70000 → 0x40000**） |
| Dock 内空间创建入口 | `0x1f07d4`（Swift 方法） | **已移除** → 改由 `WindowManager.framework` 提供 |
| 空间创建 API | `Spaces.addSpace(displayID:)` (Dock) | `WindowManager.WindowManager.synchronouslyRequestCreateManagedSpace(displayUUID: String?) throws -> UInt64` |
| removeSpace | 基址 0x1e0000 | 基址 **0x180000**（pattern 不变，命中 0x18b9a0） |
| moveSpace | 基址 0x1c0000 | 基址 **0x180000**（pattern 不变，命中 0x18c554） |
| animation-time patch | 基址 0x250000 | 基址 **0x220000**（pattern 不变，命中 0x227508） |
| setFrontWindow | pattern 从 `21 ?? ?? 34 ...` 命中 | **pattern 第 1 字节失效**（cbz 立即数变化）→ 用 `?? ?? ?? 34 7F 23 03 D5 FF C3 01 D1 F6 57 04 A9 F4 4F 05 A9 FD 7B 06 A9 FD 83 01 91`，唯一命中 **0x192bc** |
| `verify_os_version` | majorVersion 26 | **必须加 27 分支**（否则整个 SA 直接 return，所有功能失效） |

**根因**：macOS 27 起 Dock 不再自己实现空间创建（Swift `space_create_entry` 消失），改为把空间/窗口管理下沉到私有框架 `WindowManager.framework`；同时所有 pattern 搜索基址下方的函数位置整体上移/下移，且 `setFrontWindow` 的编译器布局变化导致首个字节失配。SA 的 `verify_os_version()` 没有 27 分支是"全部失效"的直接原因。

---

## 1. 静态分析流程（本次实际路径）

### 1.1 提取目标与初步扫描

```bash
sw_vers                                   # 27.0 (26A428)
defaults read /System/Library/CoreServices/Dock.app/Contents/Info.plist CFBundleVersion  # 2571.0.6.402
lipo -thin arm64e -output Dock_arm64e /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
otool -l Dock_arm64e | grep -A8 "segname __TEXT"   # vmaddr 0x100000000
```

用 Python 复刻 `hex_find_seq`（逐字节扫描 + 0x1286a0 窗口）对全部 macOS-26 pattern 在新 binary 上扫描，得到"哪些失效、命中漂移到哪里"的清单。

### 1.2 全局变量语义画像（本次最有效的技巧）

Dock 的空间/壁纸对象都是 `__DATA,__common` 里的**裸指针全局变量**（BSS，文件里为 0），无法直接判断"哪个全局是 Spaces"。

方法：
1. `dyld_info -fixups Dock_arm64e` 导出 `__objc_selrefs → 方法名` 映射；
2. 扫描 `__TEXT,__objc_stubs`（0x1002e8200–0x1002fb360），解出每个 `objc_msgSend` stub 对应的 selector；
3. 对 `__TEXT,__text` 做**寄存器级抽象解释**（跟踪 adrp/add/ldr/mov/bl），记录每次 `bl <stub>` 时 `x0` 是哪个全局变量；
4. 统计"全局变量 × 方法名"矩阵 → 得到语义指纹。

结果：

| 全局变量 | 语义（选出的方法） | 结论 |
|---------|------------------|------|
| `0x100409bb0` | `currentSpaceForDisplay:` `allUserSpaces` `currentSpaces` `switchToNextSpace:` `analyticsSpaceCount` | **Spaces 单例** |
| `0x100409c50` | `addSpace:forDisplayUUID:` `removeSpace:` `moveSpace:toDisplay:displayUUID:` `addFullscreenSpace:forDisplayUUID:` | **DPPM（WallpaperAgentDesktopPictureManager）单例** |
| `0x100409c28` | `dockConnection` `darkDock` `dragWindow` `setMainMillis:` … | Dock 设置对象（不用于 yabai） |
| `0x100409ba0` | `_handleEvent:location:flags:` `_getCornerActions:` | 热区控制器（不用于 yabai） |

### 1.3 架构变化定位

`otool -L Dock` 显示新增依赖 `/System/Library/PrivateFrameworks/WindowManager.framework`（462.0.8）。
`nm -u Dock | swift-demangle` 显示 Dock 侧 import 的 WM API：`synchronouslyRequestLayoutState/Control`、`assignWindows`、`addAgentDisconnectHandler`…**但没有空间创建**。
在 Dock 中检索 `synchronouslyRequestCreateManagedSpace` 也不存在 → 说明创建被移出 Dock。

### 1.4 从 dyld shared cache 提取 WindowManager.framework

WindowManager.framework 在磁盘上只有 Resources/_CodeSignature，**二进制仅存在于 dyld shared cache**。用 Python 直接解析 cache：

```python
# 主 cache 头: magic 'dyld_v1  arm64e'
#   u32 @16 = mappingOffset, u32 @20 = mappingCount
#   u64 @136 = imagesTextOffset, u64 @144 = imagesTextCount
# mapping 项 32B: <QQQII> = (address, size, fileOffset, maxProt, initProt)
# imagesText 项 32B: <16sQII> = (uuid, loadAddress, textSegmentSize, pathOffset)
# 每个 subcache (dyld_shared_cache_arm64e.NN) 各有自己的 header/mapping
# 路径字符串在主 cache 中; 通过 loadAddress 落在哪个 mapping 决定数据在哪个文件
```

拿到镜像后按原 Mach-O 头部重建文件（重写每个 `LC_SEGMENT_64.fileoff` 与 section `offset`），即可用 `otool -tV` 反汇编。随后：

```bash
dyld_info -exports /System/Library/PrivateFrameworks/WindowManager.framework/.../WindowManager \
  | awk '{print $2}' | xcrun swift-demangle | grep -i "space"
```

得到关键 API：

```
WindowManager.WindowManager.synchronouslyRequestCreateManagedSpace(displayUUID: Swift.String?) throws -> Swift.UInt64
WindowManager.WindowManager.synchronouslyRequestDestroySpace(Swift.UInt64) throws -> ()
WindowManager.WindowManager.provideVisibilityHintForSpace(forSpace: Swift.UInt64) throws -> ()
static WindowManager.WindowManager.shared.getter : WindowManager.WindowManager
```

对应 mangled 符号（dlsym 用，去掉前导下划线）：

| 符号 | 用途 |
|------|------|
| `$s13WindowManagerAACMa` | `type metadata accessor`（静态 getter 需要先把 metatype 放 x20） |
| `$s13WindowManagerAAC6sharedABvgZ` | 单例 getter |
| `$s13WindowManagerAAC38synchronouslyRequestCreateManagedSpace11displayUUIDs6UInt64VSSSg_tKF` | **空间创建** |
| `$s13WindowManagerAAC32synchronouslyRequestDestroySpaceyys6UInt64VKF` | 空间销毁（备用） |
| `$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ` | `String(NSString)` 桥接（构造 Swift String） |

### 1.5 Swift 调用约定（实测自二进制）

- **导出 thunk**（framework 内 0x58EC4）：

```asm
pacibsp
str  x20, [sp, #-0x20]!
stp  x29, x30, [sp, #0x10]
add  x29, sp, #0x10
ldr  x20, [x20, #0x10]     ; self = <WindowManager 实例> + 0x10 的内部对象
bl   <impl>                ; x0/x1 原样透传（String? 参数）
```

- **Dock 内同类调用点**（0x10012ecf8，`synchronouslyRequestLayoutControl`）：

```asm
ldr  x20, [x19, #0x20]     ; self
mov  x21, #0x0             ; 调用前清零 error 寄存器
bl   ...                   ; X0=返回值, X21=swift_error*（0 表示无错误）
cbz  x21, <ok>
```

→ 约定确认：**`x20 = self`，`x0/x1 = Swift String（Optional 非空即原样）`，返回 `x0`，错误 `x21`**。
- `String(NSString)` 桥接同样是 `x0 = NSString` 入参、`x0/x1 = String` 返回（Dock 0x1002cb51c 调用点实测）。

---

## 2. macOS 27 判定与补丁清单

### 2.1 版本门（`src/osax/payload.m`）

`verify_os_version()` 增加 `majorVersion == 27` 分支并置 `macOSSequoia = true`（x86_64 分支不加——macOS 27 无 Intel 版本）。

### 2.2 偏移/基址（`src/osax/arm64_payload.m`）

| 函数 | macOS 27 取值 | 说明 |
|------|--------------|------|
| `get_dock_spaces_offset` | `0x30000`（不变） | 命中 0x30a98 → 解出 Spaces 全局 0x100409bb0 |
| `get_dppm_offset` | `0x40000` | 旧基址 0x70000 会**错过** 0x509fc 的命中 |
| `get_fix_animation_offset` | `0x220000` | 命中 0x227508 |
| `get_remove_space_offset` | `0x180000` | 命中 0x18b9a0 |
| `get_move_space_offset` | `0x180000` | 命中 0x18c554 |
| `get_set_front_window_offset` | `0x10000`（不变） | pattern 改为首位通配后唯一命中 0x192bc |
| `get_add_space_offset` | `0` | 27 无 Dock 内创建入口，留 0 避免调用错误函数 |
| `get_space_create_entry_offset` | `0` | 同上 |

pattern 仅 `set_front_window` 需要改（首 4 字节从 `21 ?? ?? 34` 改为 `?? ?? ?? 34`），其余沿用 macOS 26 pattern。

### 2.3 空间创建（`src/osax/payload.m`）

```c
// init_instances(): os_version.majorVersion >= 27 时
dlopen("/System/Library/PrivateFrameworks/WindowManager.framework/Versions/A/WindowManager", RTLD_LAZY|RTLD_NOLOAD);
wm_metadata_fp            = dlsym(RTLD_DEFAULT, "$s13WindowManagerAACMa");
wm_shared_getter_fp       = dlsym(RTLD_DEFAULT, "$s13WindowManagerAAC6sharedABvgZ");
wm_create_space_fp        = dlsym(RTLD_DEFAULT, "$s13...CreateManagedSpace...tKF");
swift_string_from_objc_fp = dlsym(RTLD_DEFAULT, "$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ");
swift_error_release_fp    = dlsym(RTLD_DEFAULT, "swift_errorRelease");

// do_space_create(): 先构造 Swift String 的 displayUUID，再按 Swift 约定调用
//   x20 = WindowManager.shared, x0/x1 = String word0/word1, x21 = 0
//   返回 x0 = 新 spid, x21 = swift_error*
```

调用宏（`asm__call_wm_create_space` / `asm__call_swift_static_getter`）与既有 `asm__call_space_create_tahoe` 同风格：单块 `asm volatile` + `blr` + 完整 clobber（含 x20/x21/x30 + memory）。
宏内 asm 操作数名**不能与宏参数同名**（否则预处理器替换后 `%[name]` 失配，clang 报 "unknown symbolic operand name"）。

### 2.4 握手属性

`OSAX_ATTRIB_ADD_SPACE` 改为 `add_space_fp || space_create_entry_fp || wm_create_space_fp`——三种实现代际任一可用即上报支持，避免 daemon 误判 "payload doesn't support this macOS version"。

---

## 3. 验证

静态（已完成）：

- Python 复刻 `hex_find_seq` + 从源码提取的 27 分支 pattern，逐条验证命中位置在搜索窗口内且唯一；
- `dock_spaces`/`dppm` 两个指针型 pattern 解出的全局地址分别为 `0x100409bb0` / `0x100409c50`，与 1.2 的语义画像一致；
- `make BUILD_PATH=...` 全量编译通过（x86_64 + arm64/arm64e 均无警告）。

动态（待现场验证）：

```bash
# 1) 安装新 SA（版本 2.1.32，daemon 会因版本不匹配自动重装并重启 Dock）
yabai --load-sa

# 2) 观察 Dock 日志中的 SA 自检行
log show --last 5m --predicate 'process == "Dock"' | grep -E "yabai-sa"

# 期望看到:
#   [yabai-sa] checking for macOS 27.0.0 compatibility!
#   [yabai-sa] (0x...) dock.spaces found at ...
#   [yabai-sa] (0x...) dppm found at ...
#   [yabai-sa][WM] WindowManager entry points resolved (metadata=... shared=... createSpace=...)

# 3) 功能验证
yabai -m space --create
log show --last 1m --predicate 'process == "Dock"' | grep "\[yabai-sa\]\[WM\]"
# 期望: [yabai-sa][WM] synchronouslyRequestCreateManagedSpace returned (spid=<非0>, error=0x0)
```

---

## 4. 残余风险

1. `synchronouslyRequestCreateManagedSpace` 能否在 Dock 进程内成功执行**未做动态验证**（静态证据：Dock 自身通过 `shared` 调用同框架的 `synchronouslyRequestLayoutState` 等同步 XPC API，故实例与连接有效）。
2. `String?` 参数按"非空 String 即 payload 原样"传递（Swift ABI 规则），短于 16 字节的字符串会走 small-string 编码——displayUUID 固定 36 字符，不受影响。
3. `_displaySpaces` / `_currentSpace` 等 ivar 名称未在 macOS 27 上逐一验证（`space --focus` 的 ivar 回写若失败只影响 Dock 内部模型同步，SLS 切换仍会发生）。
4. `space --destroy` 仍走 Dock 内 `removeSpace` 函数指针（pattern 命中），未改用 WM API。

---

## 5. G3′（2026-09-15 更新）：Dock 内部创建 helper —— 静态定位全过程

### 5.1 为什么放弃 G3（框架 admin XPC）

- `WindowManager.framework` 的客户端调用落到服务端 `AdminXPCListenerDelegate.adminXPCListener(_:connection:requestsCreateManagedSpaceWithDisplayUUID:completion:)`；
- 服务端有 `WorkspaceLayoutController` / `LayoutControl` / `layoutControlHolder`，突变请求需持有 layout control 断言；
- 实测：Dock 内取 control → create → commit 仍失败，直连 `CGSSpaceCreate` 亦为 NULL —— 说明**连接身份**才是关键，而非参数。

### 5.2 关键观察：Dock 自己就有创建函数

对 Dock 反汇编做 `CGSSpaceCreate` 调用点清点，得到 2 处，均在同一族 Swift helper 内：

```asm
; helper 0x1002bb62c（参数：x0=cid, w1=flags, x2=type, x3/x4=Swift String, x5=[pid]）
...
mov  w1, #0x7575 ; movk w1, #0x6469, lsl #16   ; "uuid"
mov  x0, x25 ; bl bridgeToObjectiveC(NSString)
...
ldr  x24, [x22, #0x10]                          ; pids.count
cbz  x24, <跳过 pid 分支>
...
bl   bridgeToObjectiveC(NSDictionary)           ; options = @{type, uuid, pid}
bl   0x100101104                                ; x0 := x21（= helper 的 cid 参数）
mov  x1, x19                                    ; flags
mov  x2, x20                                    ; options
bl   _CGSSpaceCreate                            ; x0 = 新空间 id
```

该 helper 在 Dock 内有 **21 处调用点**，实参分布：

| 调用点 | flags | type | 说明 |
|---|---|---|---|
| 0x1000db410 / 0x1001423e4 / … (19 处) | 1 | 3 | 拖拽/内部临时空间等 |
| **0x1001744cc** | **0** | **0** | **用户空间**（`SLSSpaceGetType` 0/4 即 yabai 认定的 user space，见 `src/event_loop.c`） |

### 5.3 与 "+"按钮的关系（决定性证据）

`WindowManager.app`（服务端，pid 625）内存在同源函数 `0x100426ab0`：**参数布局、`@{type,uuid,pid}` 构造、`CGSSpaceCreate` 调用形态与 Dock 的 `0x2bb62c` 逐字节同构**，唯一差异是 cid：
- 服务端：`bl 0x10008b914`（服务端自己的连接）
- Dock：`bl 0x100101104` → 实际取 **Dock 懒加载缓存的 cid**（getter `0x2c2aa8`：`swift_once` → `swift_beginAccess` → `ldr w0, [x19]`，全局 `0x41e174`）

即：**用户点 "+" 走的就是这个函数**；yabai 在自己的进程（Dock）里用 Dock 的 cid 调用同一个函数，因而不再需要 admin XPC 断言。7.1.32 直连失败的原因也在此——它用的是 `SLSMainConnectionID()`，不是 Dock 缓存的 cid。

### 5.4 pattern（macOS 27.0，均唯一命中）

```
dock_space_create helper : base 0x2b0000 → 命中 0x2bb62c
  7F 23 03 D5 E6 03 1E AA ?? ?? ?? ?? FE 03 06 AA FD 7B 06 A9 FD 83 01 91 F6 03 05 AA F8 03 04 AA F9 03 03 AA F4 03 02 AA F3 03 01 AA F5 03 00 AA
dock_cid_getter          : base 0x2c0000 → 命中 0x2c2aa8
  7F 23 03 D5 FF 03 01 D1 F4 4F 02 A9 FD 7B 03 A9 FD C3 00 91 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? F3 0A 00 90 73 D2 05 91
```

### 5.5 实现要点（7.1.33 / OSAX 2.1.37）

- 调用：`asm__call_dock_space_create(cid, 0, 0, uuid_w0, uuid_w1, __swiftEmptyArrayStorage, fn, spid)`
  - `uuid` 用既有的 `String(NSString)` 桥接（`$sSS10FoundationE36…`），与 Dock 自身调用点一致
  - `pids` 传 `dlsym("__swiftEmptyArrayStorage")`（空数组单例必须传真对象：helper 命中空数组分支后会对其做 `swift_bridgeObjectRelease`）
  - 主线程调用（Dock 的每个调用点都在主线程）
- pattern 得到的是**未签名**地址 → 用普通 `blr`（只有 `dlsym()` 指针才需要 `blraaz`）
- 返回非 0 视为成功；G3 的 admin XPC 保留为回退路径

## 6. 决定性实验（2026-09-15，脱离 yabai 独立验证）

为了把"机制是否成立"与"yabai 是否接对"分开，用**独立注入器 + 最小负载**验证（不含 daemon / socket / 协议）：

```
/tmp/spacetest/minpay.dylib   ~100 行：pattern 定位 cid getter + create helper -> blr 调用 -> 打印空间数
/tmp/spacetest/loader_test    仓库 loader 的副本（注入逻辑未改，仅改 payload 路径）
```

### 6.1 先被证伪的两条路（都不在 Dock 内）

| 实验 | 结果 |
|---|---|
| 普通进程 `CGSSpaceCreate`：本进程 cid / **Dock 的 cid**（`CGSGetConnectionIDForPSN`）/ pid=自己·Dock·WindowManager / 有无 uuid | **全部 NULL**；flags=1 直接崩 |
| 普通进程 dlopen `WindowManager.framework` 调 `synchronouslyRequestCreateManagedSpace` | Swift 错误 **"Couldn't communicate with a helper application."** |

→ 创建**必须发生在 Dock 进程内**（这也解释了 7.1.30/7.1.31 的 admin XPC 与 7.1.32 的直连为何都失败）。

### 6.2 进程内最小负载的实测输出

```
[minpay] cid_getter=0x1049faaa8 create_helper=0x1049f362c
[minpay] dock cid = 1926979 (SLSMainConnectionID=1926979)   ← 假设被推翻：cid 与主连接相同
[minpay] site=0x1048ac4bc emptyArraySingleton=0x1f9ea7db8   ← 关键：literal pool 解码出真单例
[minpay] A displayUUID -> 0xcd   spaces 9 -> 10             ← 成功，返回新空间 id
[minpay] DONE spaces 9 -> 10
```

`yabai -m query --spaces` → 10（新空间 index 10）；Dock 未崩溃。

### 6.3 失败样本与教训

| 现象 | 根因 | 教训 |
|---|---|---|
| Dock 崩于 `Dock+0x2c2aa8`，`PAC_EXCEPTION` | 用 C 函数指针调用 pattern 裸地址；clang 对 C 间接调用生成 `braaz` | **未签名的裸地址用 `blr`**；签名指针/dlsym 指针用 `braaz`/`blraaz` |
| `space --destroy` 崩（`PAC_EXCEPTION`，地址带签名高位） | 把**已签名**的 `remove_space_fp` 统一改成了裸 `blr` | 签名与分支方式必须配对；该"统一"改动已回退 |
| Dock 崩于 helper 内部读 `[NULL+0x10]` | `dlsym(RTLD_DEFAULT, "__swiftEmptyArrayStorage")` 返回 **NULL**（Swift 运行时私有符号，不可 dlsym） | 与 Dock 一样**从 literal pool 解码**；且**未解析出时绝不调用** |
| 负载崩于 `slide+0x2c0000` | 把 image 基址写成 `header - 0x100000000` | image 相对 offset 要加在 **header 指向的运行时地址**上 |

### 6.4 可用配方（macOS 27.0）

```
helper(cid, flags=0, type=0, SwiftString(displayUUID), __swiftEmptyArrayStorage)  → 新空间 id
  cid   = Dock 缓存的连接 id（getter 0x2c2aa8；实测 == SLSMainConnectionID）
  uuid  = 显示器 UUID（临时生成随机 UUID 的对照分支未用上）
  pids  = literal slot（图像相对 0x3c3998）
  调用：主线程 + blr（裸地址）
```

按此配方 7.1.33/7.1.34 在 `payload.m` 的 macOS 27 分支落地。

## 附录 A：dyld shared cache 镜像提取（可复用）

```python
#!/usr/bin/env python3
"""Extract a Mach-O image from the macOS dyld shared cache (main file + subcaches)."""
import re, struct, sys
from pathlib import Path

CACHE_DIR = Path('/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld')
MAIN_NAME = 'dyld_shared_cache_arm64e'

def parse_mappings(data):
    mo, mc = struct.unpack_from('<II', data, 16)
    return [struct.unpack_from('<QQQII', data, mo + i*32)[:3] for i in range(mc)]

def load_cache():
    va_map = []
    for f in sorted(CACHE_DIR.glob(MAIN_NAME + '*')):
        d = f.read_bytes()
        if not d[:16].startswith(b'dyld_v1'):
            continue                     # skip .map/.atlas/.symbols
        for addr, size, fo in parse_mappings(d):
            va_map.append((addr, addr + size, d, fo))
    return va_map

def read_va(va_map, va, n):
    for a, b, d, fo in va_map:
        if a <= va < b:
            off = fo + (va - a)
            return d[off:off + n]
    raise ValueError(f'0x{va:x} not mapped')

def find_image(va_map, needle):
    main = (CACHE_DIR / MAIN_NAME).read_bytes()
    ito, itc = struct.unpack_from('<QQ', main, 136)
    for i in range(itc):
        base = ito + i*32
        load_addr, text_size, path_off = struct.unpack_from('<QII', main, base + 16)
        end = main.find(b'\x00', path_off)
        path = main[path_off:end].decode('utf-8', 'replace')
        if needle in path:
            return path, load_addr
    raise ValueError('image not found')

def extract(path, base, out_path, va_map):
    head = bytearray(read_va(va_map, base, 32))
    ncmds, sizeofcmds = struct.unpack_from('<II', head, 16)
    head = bytearray(read_va(va_map, base, 32 + sizeofcmds))
    off, layout, cur = 32, [], (32 + sizeofcmds + 0xfff) & ~0xfff
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', head, off)
        if cmd == 0x19:                                       # LC_SEGMENT_64
            segname = head[off+8:off+24].rstrip(b'\x00').decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', head, off+24)
            if segname == '__LINKEDIT':
                filesize = 0                                  # shared/linkedit is not per-image
            delta = cur - fileoff
            struct.pack_into('<Q', head, off + 32, cur)       # segment fileoff
            for s in range(struct.unpack_from('<I', head, off + 64)[0]):
                so = off + 72 + s*80
                sec_off = struct.unpack_from('<I', head, so + 48)[0]
                if sec_off:
                    struct.pack_into('<I', head, so + 48, sec_off + delta)
            layout.append((vmaddr, cur, filesize))
            cur += (filesize + 0xfff) & ~0xfff
        off += cmdsize
    blob = bytearray(cur)
    blob[:len(head)] = head
    for vmaddr, new_off, filesize in layout:
        if filesize:
            blob[new_off:new_off + filesize] = read_va(va_map, vmaddr, filesize)
    Path(out_path).write_bytes(bytes(blob))
    print(f'wrote {out_path} ({len(blob)} bytes)')

if __name__ == '__main__':
    needle, out = sys.argv[1], sys.argv[2]
    va_map = load_cache()
    path, base = find_image(va_map, needle)
    print(f'{path} @ 0x{base:x}')
    extract(path, base, out, va_map)
```

用法：

```bash
python3 dyld_cache_extract.py WindowManager.framework /tmp/WindowManager_extracted
dyld_info -exports /System/Library/PrivateFrameworks/WindowManager.framework/Versions/A/WindowManager \
  | awk '{print $2}' | xcrun swift-demangle > symbols.txt
otool -tV /tmp/WindowManager_extracted | grep -A 20 "^<aslr-free VA>"
```

## 附录 B：pattern 静态验证脚本（可复用）

```python
#!/usr/bin/env python3
"""Verify yabai macOS pattern strings against a Dock arm64e slice, emulating hex_find_seq."""
import re, struct, sys
from pathlib import Path

DOCK = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/dock27/Dock_arm64e')
SRC  = Path('src/osax/arm64_payload.m')
DATA = DOCK.read_bytes()
BASE = 0x100000000
WINDOW = 0x1286a0                      # hex_find_seq search window

def parse(pat):
    b, m = [], []
    for t in pat.split():
        if '?' in t: b.append(0); m.append(0)
        else:        b.append(int(t, 16)); m.append(0xFF)
    return bytes(b), bytes(m)

def find_first(pat, start):
    b, m = parse(pat)
    seg = DATA[start:start + WINDOW]
    for i in range(len(seg) - len(b)):
        if all(not m[k] or seg[i+k] == b[k] for k in range(len(b))):
            return start + i
    return None

def decode_adrp_add(off):
    adrp, add = struct.unpack_from('<II', DATA, off)
    imm = (((adrp >> 5) & 0x7ffff) << 2) | ((adrp >> 29) & 3)
    if imm & (1 << 20): imm -= 1 << 21
    imm12 = (add >> 10) & 0xfff
    if add & 0xc00000: imm12 <<= 12
    return ((BASE + off) & ~0xfff) + (imm << 12) + imm12

src = SRC.read_text()
for fn in re.findall(r'uint64_t (get_\w+_offset)\(NSOperatingSystemVersion', src):
    body = re.search(rf'uint64_t {fn}\(.*?\n\}}', src, re.S).group(0)
    m27 = re.search(r'majorVersion == 27\) \{(.*?)\n    \} else', body, re.S).group(1)
    off = int(re.search(r'return (0x[0-9a-fA-F]+|0);', m27).group(1), 16)
    pfn = fn.replace('_offset', '_pattern')
    pbody = re.search(rf'const char \*{pfn}\(.*?\n\}}', src, re.S).group(0)
    p27 = re.search(r'majorVersion == 27\) \{(.*?)\n    \} else', pbody, re.S).group(1)
    m = re.search(r'return "([^"]+)"', p27)
    if not off or not m:
        print(f'{fn:34s} offset=0x{off:x} pattern=none'); continue
    hit = find_first(m.group(1), off)
    extra = f' -> global 0x{decode_adrp_add(hit):x}' if hit and fn in ('get_dock_spaces_offset', 'get_dppm_offset') else ''
    print(f'{fn:34s} base=0x{off:<8x} hit={"0x%x" % hit if hit else "MISS"}{extra}')
```
