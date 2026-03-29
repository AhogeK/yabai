# 逆向工程 macOS 私有 API：从零到 Pattern 的完整研究方法

***

## 一、理解"Pattern 匹配"是什么

yabai 的 scripting addition 注入进 Dock.app 之后，需要调用 Dock 内部的私有函数——这些函数没有符号名（stripped binary），无法直接通过函数名调用。解决方案是：**在 Dock 的内存镜像里搜索一段特征字节序列，定位函数入口，然后强行调用它。**

```
Dock.app binary (stripped)
        │
        ▼
  [ 内存中的机器码 ]
  7F 23 03 D5    ← pacibsp (函数序言，arm64e 指针认证)
  FF C3 01 D1    ← sub sp, sp, #0x70
  E1 03 1E AA    ← mov x1, x30
  ...
        │
pattern 扫描器从 offset 0x250000 开始搜索这段字节
        │
        ▼
  找到 → 记录地址 → 当作函数指针调用
```

`??` 是通配符，代表"这个字节我不关心"，通常用来屏蔽会随编译变化的立即数、跳转偏移量等。

***

## 二、工具链与前置准备

### 必备工具

| 工具 | 用途 |
|------|------|
| **Ghidra** | 主力反编译器，免费，Apple Silicon 支持好 |
| **IDA Pro / Binary Ninja** | 商业替代，Binary Ninja 对 arm64e 支持极佳 |
| **lldb** | 动态调试，配合 Xcode 使用 |
| **otool / nm** | 查 Mach-O 结构、符号 |
| **class-dump / dsdump** | 提取 ObjC/Swift 类结构 |
| **frida** | 运行时 hook 与探测，无需重启进程 |

### 获取 Dock 二进制

```bash
# Dock.app 路径
/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock

# 但它是个 Universal Binary（x86_64 + arm64e），需要先提取目标 slice
lipo -thin arm64e /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock \
     -output ~/Desktop/Dock_arm64e

# 查看基本信息
otool -l ~/Desktop/Dock_arm64e | grep -A4 LC_SEGMENT_64
file ~/Desktop/Dock_arm64e
```

> ⚠️ macOS 系统盘上的 Dock 受 SIP 保护，但你可以直接读取，只是不能修改。逆向分析不需要写权限。

***

## 三、Ghidra 静态分析：定位目标函数

### 3.1 加载二进制

Ghidra 导入时选择 `Mach-O` 格式，Language 选 `AARCH64:LE:64:v8A`。导入后执行 Auto Analysis，勾选：
- `Demangler`
- `Objective-C`（有残留符号时很有用）
- `Stack`

### 3.2 利用字符串定位入口

Dock 虽然 stripped，但字符串常量保留着。asmvik 在代码注释里已经给了线索：

```c
// Pulling out of doBindingCommand:display (search decompiled text in ghidra)
// Pulling from function 'DPRemoteConnection::_handleEvent:'
```

在 Ghidra 里：

```
Window → Defined Strings → 搜索 "doBindingCommand" 或 "handleEvent"
```

找到字符串后，右键 → `References` → `Show References to Address`，就能跳到引用这个字符串的函数。这个函数就是目标函数，或者离目标很近。

### 3.3 从 ObjC 方法表入手

```bash
# 用 dsdump 提取所有 ObjC 方法名
dsdump --objc ~/Desktop/Dock_arm64e 2>/dev/null | grep -i "addSpace\|createSpace\|dppm\|DesktopPicture"

# 或者直接用 nm 查残留符号
nm -U ~/Desktop/Dock_arm64e | grep -i space
```

Dock 是 ObjC/Swift 混编，`-[SpacesController addSpace:]` 这类方法名可能部分保留。一旦找到方法名对应的地址，Ghidra 里直接跳过去。

***

## 四、识别函数序言与提取 Pattern

定位到目标函数后，核心工作是**提取一段稳定的特征字节**。

### 4.1 arm64e 函数序言结构

```asm
; 典型 arm64e 函数开头（pacibsp = Pointer Authentication Code for IB using SP）
pacibsp                 ; 7F 23 03 D5  ← 几乎所有函数都有，作为开头锚点
sub  sp, sp, #N         ; FF ?? 01/02/03 D1  ← N 随栈帧大小变化，用 ??
stp  x29, x30, [sp, N]  ; FD ?? ?? A9
...
```

`7F 23 03 D5`（pacibsp）是 arm64e 下几乎所有非叶子函数的第一条指令，极其稳定，是 pattern 的天然起点。

### 4.2 区分稳定字节 vs 不稳定字节

```
稳定（用确定值）：
  - 函数序言指令（pacibsp, stp x29/x30）
  - 特定寄存器操作（mov x0, x20 等具有语义的操作）
  - 固定的立即数逻辑比较

不稳定（用 ??）：
  - bl/blr 目标地址（每次编译都变）
  - adrp + add 的页偏移（地址随 ASLR 和链接变化）
  - 栈帧大小（优化级别影响）
  - 条件跳转的偏移量
```

### 4.3 实战：asmvik 的 `add_space` pattern 拆解

官方 macOS 26.4 的 pattern：

```
7F 23 03 D5  ← pacibsp（函数入口锚点）
E1 03 1E AA  ← mov x1, x30（保存链接寄存器）
48 89 FC 97  ← bl <某函数>（固定调用，97 表示 BL 指令，但目标偏移稳定）
FE 03 01 AA  ← mov x30, x1
FD 7B 05 A9  ← stp x29, x30, [sp, #0x50]
FD 43 01 91  ← add x29, sp, #0x50
F3 03        ← （后续寄存器保存，用来确保唯一性）
```

对比旧版（26.0）：

```
7F 23 03 D5  ← 相同
FF C3 01 D1  ← sub sp, sp, #0x70（旧版栈帧更大）
E1 03 1E AA  ← 相同
?? ?? 00 94  ← bl（目标变了，所以用 ??）
FE 03 01 AA  ← 相同
FD 7B 06 A9  ← stp x29, x30, [sp, #0x60]（偏移不同）
FD 83 01 91  ← add x29, sp, #0x60（偏移不同）
F3 03        ← 相同
```

26.4 的变化是：**Apple 重新编译 Dock 时，这个函数的栈帧变小了**（从 0x70 变成 0x50），导致旧 pattern 的第二条指令 `FF C3 01 D1` 对不上，匹配失败。

***

## 五、动态验证：lldb 确认函数地址

静态分析找到了疑似函数，还需要动态确认。

### 5.1 attach 到 Dock

```bash
# SIP 必须禁用，或使用 --attach-to-pid 等方式
lldb -n Dock

# 或者已经 running：
lldb --attach-name Dock
```

### 5.2 根据 offset 计算运行时地址

Dock 有 ASLR，运行时基址每次都变，需要计算：

```
(lldb) image list Dock
[  0] D3A2F... 0x0000000105000000 /System/Library/CoreServices/Dock.app/...
                ↑ 这是运行时 slide（基址）

运行时地址 = 基址 + offset
例：基址 0x105000000 + add_space offset 0x250000 = 0x105250000
```

```bash
# 在计算出的地址设断点
(lldb) br set -a 0x105250000

# 触发：用 Mission Control 创建一个 Space
# 断点命中后查看寄存器
(lldb) register read
(lldb) x/20i $pc    # 查看当前 PC 附近的反汇编
```

### 5.3 验证 pattern 的唯一性

确认找到的地址后，反过来验证这段字节在整个 Dock 二进制里是否唯一：

```bash
# 用 Python 脚本在二进制里搜索 pattern
python3 << 'EOF'
data = open('/path/to/Dock_arm64e', 'rb').read()
pattern = bytes.fromhex('7F2303D5E1031EAA4889FC97FE0301AAFD7B05A9FD430191F303')
idx = 0
while True:
    pos = data.find(pattern, idx)
    if pos == -1: break
    print(f"Found at offset: 0x{pos:X}")
    idx = pos + 1
EOF
```

如果搜到多个匹配，pattern 太短，需要加长；如果一个都没有，pattern 有误。

***

## 六、offset 是什么，怎么确定

Pattern 扫描不是从整个 Dock 二进制头开始扫，而是从一个粗糙的 offset 附近开始，原因是：

- 扫整个二进制太慢
- offset 缩小搜索范围，让 pattern 可以更短（减少误匹配）

**offset 的本质**是目标函数距离 Dock `__TEXT` 段起始的大致偏移。每次 Apple 重新编译，函数位置会轻微漂移，但通常在同一数量级。

```bash
# 在 Ghidra 里，函数地址减去 Dock 的 image base 就是 offset
# Ghidra 默认 image base 是 0x100000000（Mach-O 64）
# 函数地址 0x1002A0000 → offset = 0x2A0000
```

asmvik 的 offset 值（`0x250000`、`0x1e0000` 等）就是这样来的——Ghidra 里看到函数地址，减去 image base，得到 offset。

***

## 七、dppm 的特殊性：从 C++ 类找 ivar

`dp_desktop_picture_manager` 是 Dock 某个 C++ 类的成员变量（ivar），不是独立函数。找它的流程不同：

### 7.1 找到引用它的函数

asmvik 注释说从 `DPRemoteConnection::_handleEvent:` 里找。这是 C++ 类，Ghidra 会保留 demangled 名字。

在 Ghidra 搜索 `_handleEvent`，找到函数后反编译，找到类似这样的模式：

```c
// Ghidra 伪代码
void DPRemoteConnection::_handleEvent(id event) {
    ...
    iVar = *(id *)((char *)this + 0x70);  // ← 这个偏移就是 dppm 的 ivar offset
    if (iVar != nil) {
        [iVar handleEvent:event];
    }
    ...
}
```

对应的汇编里，从某个基址寄存器加偏移 load 一个指针，这个 load 指令序列就是 dppm pattern 的来源。

### 7.2 Pattern 对应的汇编语义

官方 macOS 26 的 dppm pattern：

```
?? ?? 00 ??   ← adrp xN, page（加载 dppm 对象的页地址，?? 因地址变化）
08 ?? ?? 91   ← add x8, xN, #offset（计算精确地址）
00 01 40 F9   ← ldr x0, [x8]（load dppm 指针到 x0）
E2 03 16 AA   ← mov x2, x22（保存某参数）
E3 03 19 AA   ← mov x3, x25
?? ?? ?? 94   ← bl <handleEvent 或类似>
```

这几条指令组合在一起，语义上就是"加载 dppm 对象，然后调用它的方法"，在整个 Dock 里具有唯一性。

***

## 八、完整工作流总结

```
新版 macOS 发布
      │
      ▼
1. 提取新 Dock binary（lipo -thin arm64e）
      │
      ▼
2. Ghidra 加载 + Auto Analysis
      │
      ▼
3. 通过字符串/ObjC方法表/已知 C++ 类名定位目标函数
      │
      ▼
4. 对比旧版函数，找出发生变化的字节（栈帧/调用目标/寄存器分配）
      │
      ▼
5. 提取稳定字节序列，不稳定位置用 ??
      │
      ▼
6. 用 Python 脚本验证 pattern 在 binary 里唯一匹配
      │
      ▼
7. lldb attach Dock，动态验证函数执行路径
      │
      ▼
8. 更新 offset（Ghidra 里函数地址 - image base）
      │
      ▼
9. 编译测试，观察 yabai 日志确认 pattern 命中
```

***

## 九、关键技巧积累

**技巧一：用 `pacibsp`（`7F 23 03 D5`）作为 pattern 开头锚点**
几乎所有 arm64e 非叶子函数都以此开头，提供稳定起点。

**技巧二：版本间 diff 用 Ghidra 的 Version Tracking 功能**
Ghidra 有内置的两个 binary 对比功能，能自动匹配相同函数、高亮差异位置，大幅节省时间。

**技巧三：frida 快速探测**

```javascript
// frida 脚本，attach 到 Dock，找 addSpace 相关函数
var dock = Process.getModuleByName("Dock");
dock.enumerateExports().filter(e => e.name.includes("Space")).forEach(e => {
    console.log(e.name, e.address);
});
```

**技巧四：`?? ?? 00 94` 代表 BL 指令（跳转）**
`94` 是 BL 的固定 opcode 高字节，前三字节是偏移量（每次编译都变），所以固定写成 `?? ?? 00 94`（同一页内的短跳转上字节通常是 00）。

**技巧五：关注 Apple WWDC session 和 OSS 工具的 Dock 相关 issue**
每次 macOS beta 发布，yabai/rectangle/aerospace 等项目的 issue 区会很快出现 pattern 失效的报告，里面常有人贴出新的 pattern——这也是快速获取信息的渠道。

# 逆向工程 macOS 私有 API：从零到 Pattern 的完整研究方法

***

## 一、理解"Pattern 匹配"是什么

yabai 的 scripting addition 以 OSAX（Open Scripting Architecture Extension）的形式被注入进 Dock.app 进程空间，之后需要调用 Dock 内部的私有函数——这些函数没有符号名（stripped binary），无法直接通过函数名调用。解决方案是：**在 Dock 的内存镜像里搜索一段特征字节序列，定位函数入口，然后强行转换为函数指针并调用它。**

```
Dock.app binary (stripped, arm64e)
        │
        ▼
  加载进内存，随机化 ASLR 基址
        │
        ▼
  yabai osax 注入同一进程
        │
        ▼
  从 offset 附近开始，按字节逐位扫描
        │
        ▼
  [ 机器码原始字节流 ]
  7F 23 03 D5    ← pacibsp
  FF C3 01 D1    ← sub sp, sp, #0x70
  E1 03 1E AA    ← mov x1, x30
  ?? ← wildcard，任意字节都可匹配
  ...
        │
  pattern 扫描器搜索命中
        │
        ▼
  找到 → 记录绝对内存地址 → 强转函数指针 → 直接 CALL
```

`??` 是通配符，代表"这个字节我不关心，任何值均视为匹配"，通常用来屏蔽：BL 的相对跳转偏移、adrp/add 的页地址、栈帧大小、编译器分配的具体寄存器号等会随编译版本漂移的字节。

### 为什么不直接用符号名？

macOS 上系统 binary 从 Monterey 起全面开启 `__LINKEDIT` strip，并且对 Dock 这类 UI 进程应用了最激进的剥离。`nm`、`objdump --syms` 只能看到外部 symbol stub，内部的 `addSpace`、`removeSpace` 等核心函数在发布版中完全没有名字，只剩下地址。

### yabai 的 pattern 扫描器是如何工作的？

以 `arm64_payload.m` 里的 `find_function` 为例（伪代码还原逻辑）：

```c
// Scan [base + offset - window, base + offset + window] for pattern
static void *find_pattern(uint8_t *base, uint64_t offset,
                          const char *pattern, size_t pattern_len) {
    uint8_t *start = base + offset - SCAN_WINDOW;
    uint8_t *end   = base + offset + SCAN_WINDOW;

    for (uint8_t *ptr = start; ptr < end - pattern_len; ptr++) {
        bool match = true;
        for (size_t i = 0; i < pattern_len; i++) {
            if (pattern[i] == '?') continue;  // wildcard
            if (ptr[i] != pattern[i]) { match = false; break; }
        }
        if (match) return ptr;
    }
    return NULL;
}
```

offset 不是用来精确定位的，而是用来缩小搜索窗口，避免全文扫描 Dock 的几十 MB 代码段。

***

## 二、工具链与前置准备

### 必备工具全景

| 工具 | 角色 | 关键能力 |
|------|------|---------|
| **Ghidra** | 静态分析主力 | 反编译、函数图、Version Tracking、Mach-O 解析 |
| **IDA Pro** | 静态分析备选（商业） | 业界最强 decompiler，arm64e PAC 支持 |
| **Binary Ninja** | 静态分析备选（商业） | arm64e 插件支持极好，脚本自动化方便 |
| **lldb** | 动态调试核心 | Apple 平台唯一官方支持调试器，PAC 感知 |
| **otool** | Mach-O 解剖 | segment/section 分布、load commands |
| **nm** | 符号残留检查 | 看哪些 extern 符号还存在 |
| **dsdump** | ObjC/Swift 元数据提取 | 方法名、协议、ivar，比 class-dump 更现代 |
| **class-dump** | ObjC 头文件还原 | 经典工具，Swift 类支持有限 |
| **frida** | 动态 hook 与探测 | 无需重编译，运行时 intercept 任意函数 |
| **jtool2** | Mach-O 瑞士军刀 | PAC 感知、Entitlements 分析、代码签名 |
| **Hopper Disassembler** | 轻量静态分析 | Mac 原生 UI，快速看单个函数很方便 |

### 环境准备

**SIP 配置**（必须做）：

```bash
# 重启进 Recovery Mode → Utilities → Terminal
csrutil disable          # 完全禁用（开发用）
# 或者更精细的方式：
csrutil enable --without debugger   # 只允许调试器 attach，其余 SIP 保留
```

**获取并拆分 Dock 二进制**：

```bash
# 查看 Dock 是否是 FAT binary
file /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock

# 拆出 arm64e slice（Apple Silicon 机器只用这个）
lipo -thin arm64e \
  /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock \
  -output ~/Desktop/Dock_arm64e

# 也复制一份旧版（用于 diff）
cp /path/to/old/Dock ~/Desktop/Dock_arm64e_old

# 检查 Mach-O 段布局，记录 __TEXT 的 vmaddr 作为 image base
otool -l ~/Desktop/Dock_arm64e | grep -A8 "segname __TEXT"
# 输出示例：
# segname __TEXT
#  vmaddr 0x0000000100000000   ← 这是 image base，非常重要
#  vmsize 0x0000000003140000
```

**记录当前 macOS 与 Dock 版本**（每次逆向前都要记）：

```bash
sw_vers
# 记录 ProductVersion 和 BuildVersion

# 获取 Dock 的 build 版本
defaults read /System/Library/CoreServices/Dock.app/Contents/Info.plist CFBundleVersion
```

> 🚨 **重要**：如果你在新版 macOS 发布后要更新 pattern，必须先对比 build version，确认 Dock 是否真的变了。很多时候小更新 Dock 根本没动，白费力气。

***

## 三、Ghidra 静态分析：系统性定位目标函数

### 3.1 项目配置与导入

**创建 Ghidra 项目**：

```
File → New Project → Non-Shared Project
File → Import File → 选择 Dock_arm64e
Format: Mach-O
Language: AARCH64:LE:64:v8A (重要！不要选 v8，要选 v8A，支持 PAC 指令)
```

**Auto Analysis 配置**（不要全勾，精选有用的）：

```
✅ Demangler (LLVM)     → 解开 Swift/C++ mangled name
✅ Objective-C          → 还原 ObjC selector、class、protocol
✅ Stack                → 推断栈变量
✅ Function Start Search → 找到没被识别的函数入口（pacibsp 锚点）
✅ DWARF                → 如果 binary 带了 dSYM 更有用
❌ Decompiler Parameter ID → 慢且经常乱猜，关掉
```

> 💡 分析完成后，先看 Ghidra 状态栏右下角识别了多少函数。Dock 一般能识别几千个，大部分都是 unnamed。

### 3.2 三种定位策略

#### 策略 A：字符串引用链（最常用，成功率最高）

asmvik 在源码注释里给了两条线索：

```c
// "Pulling out of doBindingCommand:display (search decompiled text in ghidra)"
// "Pulling from function 'DPRemoteConnection::_handleEvent:'"
```

这不是凑巧，这就是他逆向时的工作路径。在 Ghidra 里复现：

```
Window → Defined Strings（快捷键：无，从菜单走）
搜索框输入关键词：
  - "doBindingCommand"
  - "addSpace"
  - "removeSpace"
  - "DPRemoteConnection"
  - "desktopPicture"
  - "missionControl"
```

找到字符串后，**双击跳到地址**，然后：

```
右键该字符串地址 → References → Show References to Address
```

这会弹出一个引用列表，点进去就是使用该字符串的函数。从这个函数出发，往下看它的 callees，往上看谁调用它，快速定位到目标函数区域。

#### 策略 B：ObjC/Swift 元数据直读

即便 symbol 被 strip，ObjC runtime 所需的 metadata 不能被完全剥离，因为 runtime 要靠这些数据来 dispatch 消息。Ghidra 的 ObjC 分析器会自动识别这些：

```
Window → Symbol Tree → Classes → 展开
搜索：Spaces、Space、Desktop、Display、Mission
```

会看到类似 `SpacesController`、`ManagedSpace` 等保留类名，它们对应的方法可以直接跳到反汇编。

用命令行更快验证：

```bash
# dsdump 比 class-dump 更能处理 Swift 和混编情况
dsdump --objc ~/Desktop/Dock_arm64e 2>/dev/null

# 如果只想看方法名：
dsdump --objc ~/Desktop/Dock_arm64e 2>/dev/null | grep -i "space\|addSpace\|createSpace"

# nm 看 C++ 残留符号（往往有 demangled 的 C++ 类名）
nm -U ~/Desktop/Dock_arm64e | c++filt | grep -i "DPRemote\|Desktop\|Space"
```

#### 策略 C：从已知 stub 反向定位（最暴力有效）

Dock 需要调用 `objc_msgSend`、`swift_retain`、`objc_release` 等 runtime 函数，这些调用点在 Ghidra 里以 `symbol stub` 形式保留了名字。

思路是：**目标函数一定会在合适的时机调用这些 stub，从 stub 的 cross-reference 里缩小范围。**

```
Symbol Tree → symbol stub → objc_msgSend
右键 → References → Show References to Address
筛选：找那些调用 objc_msgSend 且前后出现 "addSpace" 相关字符串引用的函数
```

### 3.3 Ghidra 反编译窗口的正确阅读方式

Dock 是 ObjC/Swift/C++ 混编，Ghidra 的 decompiler 对其输出经常是这样的：

```c
// Ghidra 伪代码（实际 stripped 后的输出）
void FUN_10022ab54(undefined8 param_1, undefined8 param_2, ...) {
    ulong uVar1;
    ulong uVar2;
    // ... 大量临时变量
    
    (**(code **)(PTR_FUN_10047ea740 + 0))(param_1, 0x17);
    // ↑ 这是 objc_msgSend，第二个参数是 selector 指针
    
    uVar1 = FUN_1001f07d8(uVar2); // ← 这就是 add_space helper
}
```

**关键阅读技巧**：

- 看到 `(**(code **)(...))` 形式，通常是 ObjC 消息发送或函数指针调用
- 看到 `PTR_FUN_xxx` 后面加偏移量，通常是从全局变量表取对象
- 伪代码里的 `param_1` 大概率是 `self`，`param_2` 是 `_cmd`（selector）
- 遇到一大堆类型为 `undefined8` 的参数，说明 Ghidra 没能推断出类型，需要手动标注

**手动辅助 Ghidra 推断**（极其有用）：

```
右键函数入口 → Edit Function Signature
手动改名：FUN_10022ab54 → add_space_coordinator
手动标注参数类型：param_1 → self (id), param_2 → selector (SEL)
```

标注完成后 Ghidra 会重新推断，decompiler 输出会明显变清晰。

### 3.4 Version Tracking：两版本 Binary 对比

这是最重要也最容易被忽略的功能，每次 macOS 升级后这是你的第一工作：

```
File → New Project → 新建一个专门用于对比的项目
Tools → Version Tracking
```

操作步骤：

```
1. Source Program  = 旧版 Dock_arm64e（已经有你标注好的函数名）
2. Destination     = 新版 Dock_arm64e（刚拆出来的）
3. Run Correlators（相关性算法）：
   ✅ Exact Function Instructions Match   → 完全没变的函数，直接匹配
   ✅ Duplicate Function Instructions     → 模板函数
   ✅ Function Reference                  → 通过调用关系推断
4. 执行后查看 Results：
   - 绿色 = 高置信度匹配（可以直接把旧标注复制过来）
   - 黄色 = 中置信度（需要手动确认）
   - 未匹配 = 函数完全被重写或位置发生大跳变（重点关注）
```

> 💡 **实战经验**：对于 yabai 关心的那几个 Dock 函数，每次 macOS 更新通常只有 1~2 个函数发生真正的变化，剩下的只是地址漂移（offset 变了但代码没变）。Version Tracking 能瞬间告诉你哪个函数真的变了，不需要全部重逆。

***

## 四、ARM64e 指令集深度解析：识别函数序言与提取 Pattern

这一节是整个报告的核心，不理解这里就无法独立写 pattern。

### 4.1 ARM64 调用约定完整速查

| 寄存器 | 别名 | 角色 | 跨函数调用是否保留？ |
|--------|------|------|---------------------|
| `x0` | — | 第 1 个参数 / 返回值 | ❌ caller-saved |
| `x1` | — | 第 2 个参数 | ❌ caller-saved |
| `x2~x7` | — | 第 3~8 个参数 | ❌ caller-saved |
| `x8` | — | 间接返回值指针 / 临时 | ❌ caller-saved |
| `x9~x15` | — | 临时寄存器 | ❌ caller-saved |
| `x16~x17` | `ip0/ip1` | 内联 PLT 临时 | ❌ caller-saved |
| `x18` | — | 平台保留（不用） | — |
| `x19~x28` | — | **保留寄存器** | ✅ callee-saved |
| `x29` | `fp` | 帧指针 | ✅ callee-saved |
| `x30` | `lr` | 链接寄存器（返回地址） | ❌ caller-saved（但被保存） |
| `sp` | — | 栈指针 | ✅ 始终对齐 16 字节 |

**关键推论**：当你在 LLDB 里 `frame select 1` 切到调用者，caller 函数里 `$x19~$x28` 里存的东西，就是该函数整个生命周期都需要的对象——通常就是 `self` 和最重要的几个业务对象。

### 4.2 ARM64e 特有机制：PAC（Pointer Authentication）

arm64e 是 Apple Silicon 专有的扩展 ISA，加入了 PAC 硬件特性，所有返回地址和函数指针都携带签名，防止 ROP 攻击。逆向时会频繁看到：

| 指令 | 含义 | 机器码 |
|------|------|--------|
| `pacibsp` | 用 SP 签名 LR，存回 LR | `7F 23 03 D5` |
| `autibsp` | 验证并恢复 LR | — |
| `retab` | 验证返回地址并 ret | `FF 0F 5F D6` |
| `pacia x16, x17` | 用 x17 签名 x16 | `30 02 C1 DA` |
| `blraaz x16` | 不带签名验证直接调用 | — |

**对 pattern 提取的影响**：`pacibsp`（`7F 23 03 D5`）几乎是所有 arm64e 非叶子函数的固定第一条指令，极其稳定，作为 pattern 的天然起点。但有少数情况（例如 leaf function、尾调用优化）不会有这条指令，需要特殊处理。

### 4.3 完整函数序言结构与对应机器码

```asm
; 典型大型 arm64e 函数序言，完整注释

pacibsp                         ; 7F 23 03 D5 ← 签名 LR，所有非叶子函数的第一条
sub  sp, sp, #0xf0              ; FF C3 03 D1 ← 分配栈空间（0xf0 = 240 bytes）
                                ;              注意 D1 是 SUB 的 opcode
                                ;              前 3 字节 FF C3 03 是 #0xf0 的编码
                                ;              栈帧大小变化时这 3 字节会变 → 用 ??
stp  d13, d12, [sp, #0x60]      ; 6D 06 33 ED ← 保存浮点寄存器（Swift 常用）
stp  d11, d10, [sp, #0x70]      ; 6D 07 2B EB
stp  d9,  d8,  [sp, #0x80]      ; 6D 08 23 E9
stp  x28, x27, [sp, #0x90]      ; A9 09 6F FC ← 保存整数 callee-saved 寄存器
stp  x26, x25, [sp, #0xa0]      ; A9 0A 67 FA
stp  x24, x23, [sp, #0xb0]      ; A9 0B 5F F8
stp  x22, x21, [sp, #0xc0]      ; A9 0C 57 F6
stp  x20, x19, [sp, #0xd0]      ; A9 0D 4F F4
stp  x29, x30, [sp, #0xe0]      ; A9 0E 7B FD ← 保存帧指针和链接寄存器
add  x29, sp, #0xe0             ; FD 43 03 91 ← 设置帧指针指向 fp 保存位置
```

**从 yabai 实际 pattern 反向解读**（以 macOS 26.4 的 `add_space` 为例）：

```
7F 23 03 D5   = pacibsp                    ← 函数入口，固定
E1 03 1E AA   = mov x1, x30               ← 把 LR 保存到 x1（非标准序言，暗示紧随 bl）
48 89 FC 97   = bl <目标 #-0x1de6c0>      ← 固定调用，偏移已知（97结尾 = BL encoding的固定位）
FE 03 01 AA   = mov x30, x1               ← 恢复 LR
FD 7B 05 A9   = stp x29, x30, [sp, #0x50] ← 栈帧 0x50，比旧版小
FD 43 01 91   = add x29, sp, #0x50
F3 03         = （stp x19, ... 的开头）   ← 后续寄存器保存，加长保证唯一性
```

**对比旧版 macOS 26.0**：

```
7F 23 03 D5   = pacibsp               ← 相同
FF C3 01 D1   = sub sp, sp, #0x70    ← 栈帧 0x70，这行在 26.4 消失了！
E1 03 1E AA   = mov x1, x30          ← 相同
?? ?? 00 94   = bl <某处>            ← 目标偏移变了，用 ??
FE 03 01 AA   = mov x30, x1          ← 相同
FD 7B 06 A9   = stp x29, x30, [sp, #0x60] ← 偏移 0x60，因为栈帧还是 0x70
FD 83 01 91   = add x29, sp, #0x60
F3 03         ← 相同
```

**根本原因**：Apple 在 macOS 26.4 重新编译 Dock 时，优化了 `add_space` 对应函数（猜测是内联了某个 helper 调用，导致栈上不再需要那么多空间），栈帧从 `0x70` 缩减到 `0x50`，整个序言布局随之改变，导致旧 pattern 失效。

### 4.4 如何判断哪些字节应该用 `??`：决策树

```
该字节是否与编译器寄存器分配决策有关？
  ├─ 是 → 用 ??（例如 adrp/add 里的 xN 寄存器号）
  └─ 否 ↓

该字节是否是跳转偏移（BL/B/B.cond 的目标偏移）？
  ├─ 是 → 用 ??（每次链接都变）
  └─ 否 ↓

该字节是否是栈帧分配大小的一部分？
  ├─ 是 → 用 ??（优化级别影响）
  └─ 否 ↓

该字节是否是固定的指令 opcode 的一部分？
  ├─ 是 → 用确定值（例如 BL 的高字节 94、pacibsp 的 D5）
  └─ 否 ↓

该字节代表的寄存器操作语义是否固定？
  ├─ 是 → 用确定值（例如 E1 03 1E AA = mov x1, x30 语义固定）
  └─ 否 → 用 ??
```

### 4.5 ARM64 机器码编码速查（pattern 编写时最高频用到）

**BL 指令编码**（无条件跳转并链接）：

```
BL offset：
bits [31:26] = 100101  → 最高字节固定为 0x94~0x97 范围
bits [25:0]  = 26位有符号立即数偏移 / 4

所以 pattern 里 BL 固定写成：
  ?? ?? ?? 94  （同页内短跳）
  ?? ?? 00 94  （更近的跳转，高字节恰好是 00）
  ?? ?? FF 97  （向后跳转，高字节是 FF 因为符号扩展）
```

**SUB SP 指令编码**（栈帧分配）：

```
SUB sp, sp, #imm：
Encoding = 0xD1 [opcode] + imm 编码

常见栈帧大小对应字节：
  #0x10  → 47 00 00 D1  → 通常用 ?? 00 00 D1 或全 ??
  #0x70  → FF C3 01 D1
  #0xF0  → FF C3 03 D1
  #0x100 → FF 03 04 D1
```

**LDR/STR 偏移编码**：

```
LDR x0, [x8, #offset]：
offset 编码在指令的 bits[21:10]，12-bit scaled

所以 LDR 的偏移字节几乎必然用 ??，只保留固定的寄存器部分
```

***

## 五、动态验证：LLDB 系统性工作流

### 5.1 正确 attach 到 Dock

```bash
# 方式一：通过进程名 attach（推荐）
sudo lldb -n Dock

# 方式二：通过 PID
sudo lldb -p $(pgrep -x Dock)

# attach 后立即获取 ASLR slide
(lldb) image list -o -f Dock
# 输出示例：
# [  0] 0x0000000004374000 /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
#                           ↑ 这是 slide
```

**运行时地址公式**：

```
runtime_address = image_base (0x100000000) + slide + static_offset
                = 0x100000000 + 0x04374000 + 0x001f07d8
                = 0x1045647D8
```

### 5.2 断点策略与触发技巧

**在候选函数入口下断点**：

```bash
(lldb) br set -a 0x1045647D8
# 验证：输出应该类似
# Breakpoint 1: where = Dock`___lldb_unnamed_symbol_1001f07d8, address = 0x1045647d8
```

**触发断点**：

```
呼出 Mission Control（F3 或 Control+↑）
点击右上角 "+" 号创建新 Space
此时 CPU 命中断点，lldb 控制台出现 "Process stopped"
立即切回终端开始分析，不要在 UI 上做任何操作
```

**断点命中后的第一件事——确认你在正确的地方**：

```bash
(lldb) x/8i $pc
# 应该看到函数序言：pacibsp, stp, sub 等
# 如果第一条不是 pacibsp，说明 offset 算错了，或 pattern 位置偏移了
```

### 5.3 调用栈深度分析

断点命中后最重要的是先看 `bt`（backtrace），理解你在整个调用链的位置：

```bash
(lldb) bt 30   # 打印 30 层调用栈
```

**如何读 stripped 调用栈**：

```
* frame #0: 0x00000001045647d8 Dock`___lldb_unnamed_symbol_1001f07d8
  ↑ 这是你下断的函数，1001f07d8 = static offset

  frame #1: 0x000000010459ebb8 Dock`___lldb_unnamed_symbol_10022ab54 + 100
  ↑ 调用者，+100 表示执行 bl 的位置距函数入口 100 字节处
  → 100 / 4 = 第 25 条指令执行了 bl

  frame #15: 0x000000018a3f6760 HIServices`mshPerform + 20
  ↑ 还有符号的系统框架，这是事件到达 Dock 的入口

  frame #16-19: CoreFoundation RunLoop
  ↑ 标准事件循环，所有 UI 事件的起点
```

**根据 static offset 计算 frame 对应的 Ghidra 地址**：

```
frame #1 offset = 0x10022ab54
Ghidra 地址 = image_base + offset = 0x100000000 + 0x10022ab54
             不对！offset 本身就是相对 0 的，Ghidra 里直接搜 0x10022ab54
```

### 5.4 寄存器深度分析

**ARM64 参数寄存器读取**：

```bash
(lldb) register read x0 x1 x2 x3 x4 x5 x6 x7
# x0 = self (ObjC) 或第1参数
# x1 = _cmd (ObjC selector) 或第2参数
# x2~x7 = 后续参数
```

**保留寄存器（切到上层 frame 后读）**：

```bash
(lldb) frame select 1
(lldb) register read x19 x20 x21 x22 x23 x24
# 这里的值是 frame #1 函数的业务对象，通常就是我们要找的控制器
```

**尝试将裸指针解释为对象**：

```bash
# 方式一：直接 po（Print Object），对 ObjC 对象有效
(lldb) po $x19
# 如果是 ObjC 对象，输出类似：<SpacesBarWindowController: 0x76d7b6800>

# 方式二：强制类型转换（绕过编译器类型检查）
(lldb) po (id)$x19

# 方式三：Swift 对象用 unsafeBitCast
(lldb) expr -l Swift -O -- unsafeBitCast(0x76d7b6800, to: AnyObject.self)

# 方式四：读取 isa 指针，手动解析类名
(lldb) x/xg $x19           # 读第一个 8 字节（isa 指针）
(lldb) po 0x<isa_value>    # 尝试解析为类指针
```

### 5.5 内存取证：当对象 Dump 失败时

当 `po` 失败（Swift metadata stripped），改用内存直读：

```bash
# 以 8 字节为单位读取 N 个 quadword（64位值）
(lldb) x/16xg $x20
# 输出：
# 0x76c850480: 0x0001800001047ea745  0x000000076d5ce080   ← 第一个是 isa（含 PAC tag），第二个是第一个 ivar
# 0x76c850490: 0x0000000000000003    0x000000076d635ea0   ← 可能是计数/枚举+另一个对象指针
# ...

# 对每个疑似对象指针尝试 po
(lldb) po (id)0x000000076d5ce080   # 如果是 ObjC 对象，成功打印类名
(lldb) x/8xg 0x000000076d5ce080   # 如果 po 失败，继续读更深层内存
```

**ObjC 对象内存布局**（每次 dump 后都按这个框架解读）：

```
offset +0x00: isa pointer (8 bytes) → 指向类对象，在 arm64e 下含 PAC tag
offset +0x08: 第一个 ivar
offset +0x10: 第二个 ivar
offset +0x18: 第三个 ivar
...
（每个 ivar 占用与类型对应的字节数，对齐到 8 字节）
```

**Swift 对象内存布局**（与 ObjC 不同）：

```
offset +0x00: isa / metadata pointer（8 bytes）
offset +0x08: reference count（8 bytes，Swift ARC）
offset +0x10: 第一个 stored property
offset +0x18: 第二个 stored property
...
```

### 5.6 使用 lldb Python scripting 自动化分析

手工 `po` 每个寄存器很慢，lldb 支持 Python scripting，可以批量扫描：

```python
# 在 lldb 里直接执行 Python：
(lldb) script
>>> import lldb
>>> target = lldb.debugger.GetSelectedTarget()
>>> process = target.GetProcess()
>>> thread = process.GetSelectedThread()
>>> frame = thread.GetSelectedFrame()

# 批量读取保留寄存器
>>> regs = frame.GetRegisters()
>>> for regGroup in regs:
...     for reg in regGroup:
...         if reg.GetName() in ['x19','x20','x21','x22','x23','x24']:
...             print(f"{reg.GetName()} = {reg.GetValue()}")

# 或者存为 .py 文件，通过 command script import 加载
```

**更实用的：读取对象的 class name**（绕过 Swift stripped metadata）：

```python
>>> import lldb, struct

def read_classname(process, addr):
    err = lldb.SBError()
    # Read isa
    isa_raw = process.ReadUnsignedFromMemory(addr, 8, err)
    # Strip PAC tag（arm64e 上 isa 的高 19 位是 PAC，实际类指针需要 mask）
    isa = isa_raw & 0x0007ffffffffffff
    # Read class name pointer (offset +0x10 from class object is name in ObjC runtime)
    name_ptr = process.ReadUnsignedFromMemory(isa + 0x10, 8, err)
    name = process.ReadCStringFromMemory(name_ptr, 128, err)
    return name
```

***

## 六、offset 是什么，完整推导方法

### 6.1 offset 的精确定义

yabai 里的 offset（如 `get_add_space_offset` 返回的 `0x250000`）是：

```
offset = function_vmaddr - __TEXT_vmaddr
       = function_vmaddr - 0x100000000
```

这是函数在 arm64e slice 里，相对于 `__TEXT` 段起始地址的静态偏移。它不随 ASLR 变化，每次 Dock 重启 offset 都是同一个值。

### 6.2 在 Ghidra 里读取 offset

```
1. 在 Ghidra 函数列表 / 反汇编窗口找到目标函数
2. 看地址栏：例如显示 0x10022ab54
3. offset = 0x10022ab54 - 0x100000000 = 0x22ab54
4. 但 yabai 用更宽松的 offset（函数附近的大概位置），扫描时会在 offset ± WINDOW 内搜索
```

### 6.3 offset 的精度权衡

| offset 精度 | 优点 | 缺点 |
|------------|------|------|
| 精确到函数入口 | pattern 可以更短 | 函数整体漂移后 offset 完全不再有效 |
| 粗糙到 0x10000 对齐 | 函数轻微漂移仍能命中 | pattern 必须更长才能保证唯一性 |
| yabai 的做法 | 对齐到 0x10000（如 0x250000），窗口内搜索 | 平衡了两者 |

### 6.4 每次系统更新后的 offset 更新方法

```bash
# 步骤1：确认 Dock 版本真的变了
defaults read /System/Library/CoreServices/Dock.app/Contents/Info.plist CFBundleVersion

# 步骤2：用 Version Tracking 找到旧函数在新 binary 里的位置
# （见第三节 3.4 的 Ghidra Version Tracking 操作）

# 步骤3：新函数地址 - 0x100000000 = 新 offset

# 步骤4：或者用 Python 直接搜
python3 - <<'EOF'
import sys

def search_pattern(binary_path, hex_pattern):
    with open(binary_path, 'rb') as f:
        data = f.read()
    
    # 解析 pattern（支持 ?? 通配符）
    parts = hex_pattern.split()
    pattern = [(None if p == '??' else int(p, 16)) for p in parts]
    
    results = []
    for i in range(len(data) - len(pattern)):
        match = True
        for j, byte in enumerate(pattern):
            if byte is not None and data[i+j] != byte:
                match = False
                break
        if match:
            results.append(hex(i))
    
    return results

# 用旧 pattern 在新 binary 里搜，找到新 offset
old_pattern = "7F 23 03 D5 FF C3 01 D1 E1 03 1E AA ?? ?? 00 94 FE 03 01 AA"
results = search_pattern('/path/to/new/Dock_arm64e', old_pattern)
print(f"Found at: {results}")

# 如果旧 pattern 找不到，改用更短的稳定前缀重新定位
EOF
```

***

## 七、dppm 的特殊性：C++ ivar 偏移定位

### 7.1 dppm 是什么

`dp_desktop_picture_manager`（dppm）不是一个独立函数，而是某个 C++ 类（很可能是 `DPRemoteConnection` 或其持有者）的**成员变量**，它的类型是一个 ObjC 对象指针。yabai 需要这个偏移来找到 dppm 对象，然后对它做操作。

### 7.2 从 C++ 类 ivar 定位 pattern 的完整流程

**第一步**：在 Ghidra 里找到 `DPRemoteConnection::_handleEvent:` 函数

```
Symbol Tree → 搜索 "handleEvent"
或
Window → Defined Strings → 搜索 "handleEvent"，追引用
```

**第二步**：看 decompiler 里 `this` 指针的使用

```c
// Ghidra 伪代码示例
void DPRemoteConnection::_handleEvent(id event) {
    id *local_ptr;
    
    // ↓↓↓ 核心：从 this（x0）偏移 0x70 处 load 一个指针
    local_ptr = *(id **)((char *)this + 0x70);
    
    if (local_ptr != nil) {
        objc_msgSend(local_ptr, sel_handleEvent, event);
    }
}
```

`0x70` 就是 dppm 在 `DPRemoteConnection` 对象内部的 ivar 偏移。

**第三步**：对应到汇编

```asm
; 上面伪代码对应的汇编（简化）
adrp  x8, <page>      ; ?? ?? 00 ??  ← 加载 DPRemoteConnection 单例的页地址
add   x8, x8, #<off>  ; 08 ?? ?? 91  ← 计算精确地址
ldr   x0, [x8]        ; 00 01 40 F9  ← load DPRemoteConnection 指针到 x0
ldr   x0, [x0, #0x70] ; 00 1C 40 F9  ← load dppm ivar（偏移 0x70，这个固定！）
bl    <handleEvent>    ; ?? ?? ?? 94  ← 调用方法
```

`00 1C 40 F9` 是 `ldr x0, [x0, #0x70]` 的机器码，其中 `#0x70` 对应的 12 位 scaled offset 编码进入 bits[21:10]，值如果变化这个字节会变——这就是 dppm 版本间变化的根源：**dppm 在 DPRemoteConnection 对象里的 ivar 偏移随 Apple 修改类定义而变化。**

### 7.3 动态验证 ivar 偏移

```bash
# attach 到 Dock，在 _handleEvent 附近设断点
# 命中后：

(lldb) frame select 0
(lldb) po $x0   # 打印 this 指针对应的对象
# 输出：<DPRemoteConnection: 0x76d5da940>

# 读取 offset 0x70 处的值
(lldb) x/xg ($x0 + 0x70)
# 输出：0x76d5da940 + 0x70 的内存 → 如果是有效指针，就是 dppm 对象

(lldb) po (id)*((id *)($x0 + 0x70))
# 如果输出类名包含 "DesktopPicture" 相关，说明 0x70 是正确偏移
```

***

## 八、完整工作流：从新版 macOS 到更新 Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│  macOS 新版本发布（Beta 或正式）                                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 1：判断 Dock 是否真的变了                                     │
│  defaults read .../Dock.app/Info.plist CFBundleVersion           │
│  如果 version 相同 → 不需要更新 pattern，止步                       │
└────────────────────────┬────────────────────────────────────────┘
                         │ Dock 确实变了
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 2：提取新 Dock arm64e slice                                  │
│  lipo -thin arm64e Dock -output Dock_arm64e_new                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 3：Ghidra Version Tracking                                  │
│  旧版（已标注）→ 新版（未标注）                                        │
│  查看哪些函数 "未匹配" 或 "低置信度匹配"                                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 4：对每个需要更新的目标函数                                     │
│  4a. Ghidra 里对比新旧反汇编，找出差异字节                             │
│  4b. 判断差异是：                                                   │
│      - 栈帧大小变化 → 修改栈帧相关 ?? 或确定值                         │
│      - BL 目标变化 → 确认 ?? 是否已覆盖                              │
│      - 函数整体被重写 → 需要重新提取 pattern                           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 5：Python 脚本验证新 pattern 唯一性                            │
│  在新 binary 里搜索：                                               │
│  - 搜到 0 个 → pattern 仍然错误                                     │
│  - 搜到 1 个 → 唯一匹配，验证 offset                                 │
│  - 搜到多个 → pattern 太短，需要加长                                  │
└────────────────────────┬────────────────────────────────────────┘
                         │ 搜到 1 个
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 6：LLDB 动态验证                                             │
│  6a. attach 到 Dock，算运行时地址                                   │
│  6b. 在新 pattern 命中的函数入口设断点                                │
│  6c. 触发 Mission Control 点击 + 号                                │
│  6d. 断点命中 → 确认 bt 调用链合理 → 确认寄存器状态符合预期             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 7：更新 arm64_payload.m                                     │
│  更新对应的 get_xxx_pattern() 和 get_xxx_offset() 函数              │
│  添加 minorVersion 分支或修改现有 26.x 分支                           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 8：编译测试                                                   │
│  make && ./bin/yabai                                             │
│  查看 yabai 日志：确认 "scripting addition loaded" 且功能正常          │
└─────────────────────────────────────────────────────────────────┘
```

***

## 九、关键技巧全面扩充

### 技巧一：`pacibsp` 作为稳定锚点，以及例外情况

`7F 23 03 D5` 是 arm64e 非叶子函数的标准第一条指令，极其稳定。**例外**：

- **叶子函数**（不调用任何其他函数的小函数）没有 pacibsp，直接是业务指令
- **Block invoke 函数**的入口格式略有不同
- **Swift 的 thunk（跳板）函数**通常非常短，可能直接是 `b` 指令

如果 pattern 搜索命中了叶子函数或 thunk，会在运行时出现崩溃（因为函数语义不对），需要往 offset 附近找真正的非叶子入口。

### 技巧二：Version Tracking 的正确使用姿势

Ghidra Version Tracking 有多种 Correlator，要按顺序运行：

```
① Exact Byte Match          → 最快，先跑完全没变的函数
② Exact Function Instructions Match → 代码相同但地址变了
③ Duplicate Function Instructions   → 模板化函数
④ Function Reference Correlator     → 通过调用关系推断
⑤ Manual Matching                   → 对实在匹配不上的手动拖拽
```

每次运行完 correlator，接受置信度高的匹配（绿色），让旧版标注自动转移到新版。

### 技巧三：Frida 快速探测，比 LLDB 更轻量

```javascript
// frida-script.js
// 列出 Dock 里所有包含 "Space" 的导出符号
Java.perform(() => {});

var dock = Process.getModuleByName("Dock");

// 枚举所有导出（stripped 后基本为空，但 ObjC selectors 是例外）
dock.enumerateExports().forEach(exp => {
    if (exp.name.toLowerCase().includes("space")) {
        console.log(`Export: ${exp.name} @ ${exp.address}`);
    }
});

// 更有用：Hook objc_msgSend，过滤包含 "Space" 的 selector
Interceptor.attach(Module.getExportByName(null, "objc_msgSend"), {
    onEnter(args) {
        try {
            var sel = args[1].readUtf8String();
            if (sel && sel.toLowerCase().includes("space")) {
                console.log(`[objc_msgSend] ${new ObjC.Object(args[0]).$className} → ${sel}`);
            }
        } catch(e) {}
    }
});
```

```bash
# 使用方式
frida -n Dock -l frida-script.js
# 然后在 UI 上触发 Mission Control → +
# 观察控制台输出，找到调用了 Space 相关 selector 的对象
```

### 技巧四：`BL` 指令机器码的完整解码

arm64 BL 指令是 4 字节，编码格式：

```
[31] [30:26]   [25:0]
  1  00101   imm26 (26-bit signed offset, in units of 4 bytes)

最高字节 = 0x94~0x97（取决于 imm26 的高 2 位）
  0x94 = 100 101 00 ... （offset 正向较近）
  0x95 = 100 101 01 ...
  0x96 = 100 101 10 ...
  0x97 = 100 101 11 ...（offset 向后，负数）
```

在 pattern 里：

```
向前跳转（调用前面的函数）：通常 ?? ?? 00 94 或 ?? ?? FF 97
向后跳转（调用后面的函数）：通常 ?? ?? FF 97 或 ?? ?? 00 94
同一段内任意：            ?? ?? ?? 94
```

> 💡 **asmvik 在 macOS 26.4 pattern 里用了 `48 89 FC 97`，这是一个精确的固定 BL，说明该函数在多版本间 BL 目标稳定（或 asmvik 验证过这个 BL 在 26.x 系列里不变）。这是比 `?? ?? ?? 94` 更强的约束，能帮助唯一定位。**

### 技巧五：用 Python 脚本进行多版本 Pattern 健康检查

每次系统更新后，先用这个脚本快速检查所有现有 pattern 是否还有效：

```python
#!/usr/bin/env python3
import sys, os

def match_pattern(data, hex_pattern):
    """Match a hex pattern with ?? wildcards against binary data."""
    parts = hex_pattern.strip().split()
    pattern = [(None if p == '??' else int(p, 16)) for p in parts]
    results = []
    
    for i in range(len(data) - len(pattern)):
        if all(b is None or data[i+j] == b for j, b in enumerate(pattern)):
            results.append(i)
    return results

# yabai 所有 pattern（从 arm64_payload.m 摘录）
PATTERNS_26 = {
    "dock_spaces": "?8 ?? ?? ?? 08 ?? ?? 91 00 01 40 F9 E2 03 13 AA ?? ?? ?? 94 ?? ?? ?? ?? 08",
    "dppm":        "?? ?? 00 ?? 08 ?? ?? 91 00 01 40 F9 E2 03 16 AA E3 03 19 AA ?? ?? ?? 94",
    "add_space_26_0": "7F 23 03 D5 FF C3 01 D1 E1 03 1E AA ?? ?? 00 94 FE 03 01 AA FD 7B 06 A9 FD 83 01 91 F3 03",
    "add_space_26_4": "7F 23 03 D5 E1 03 1E AA 48 89 FC 97 FE 03 01 AA FD 7B 05 A9 FD 43 01 91 F3 03",
    "remove_space": "7F 23 03 D5 FF ?? ?? D1 FC ?? ?? A9 FA ?? ?? A9 F8 ?? ?? A9 F6 ?? ?? A9 F4 ?? ?? A9 FD ?? ?? A9 FD ?? ?? 91 ?? 03 03 AA F5 03 02 AA F4 03 01 AA",
    # ... 其余 pattern
}

def main():
    if len(sys.argv) < 2:
        print("Usage: check_patterns.py <Dock_arm64e_path>")
        sys.exit(1)
    
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
    
    for name, pattern in PATTERNS_26.items():
        results = match_pattern(data, pattern)
        status = "✅" if len(results) == 1 else ("❌ NOT FOUND" if len(results) == 0 else f"⚠️  AMBIGUOUS ({len(results)} matches)")
        offsets = [hex(r) for r in results]
        print(f"{status} {name}: {offsets}")

if __name__ == "__main__":
    main()
```

运行后立刻知道哪个 pattern 失效，不用猜。

### 技巧六：`_ivarDescription` 与 Swift Mirror 失效时的替代方案

```bash
# ObjC 对象有效，但 Swift 对象 dump() 无输出时：

# 方案1：读取 runtime class metadata
(lldb) expr (void)NSLog(@"%@", [$x19 _ivarDescription])
# 在系统日志里查看（Console.app 过滤 Dock）

# 方案2：用 Objective-C Runtime 遍历 ivar
(lldb) expr -l ObjC -O -- @import ObjectiveC; \
    unsigned int count = 0; \
    Ivar *ivars = class_copyIvarList(object_getClass((id)$x19), &count); \
    for (int i = 0; i < count; i++) { \
        NSLog(@"ivar[%d]: %s at offset %td", i, ivar_getName(ivars[i]), ivar_getOffset(ivars[i])); \
    } \
    free(ivars);

# 方案3：直接读内存 + 对已知字段偏移做猜测
# 先 x/32xg $x19，把前 256 字节全打印出来
# 逐个对像素大小合理的指针做 po，找到有意义的对象
```

### 技巧七：关注社区 issue 与 Apple Beta Release Notes

每次 macOS beta 发布后，以下来源会很快提供线索：

- **yabai issues**：https://github.com/koekeishiya/yabai/issues — 用户报告崩溃，维护者可能直接贴 pattern
- **aerospace/rectangle issues**：这些工具也依赖 Dock 私有 API，他们的 issue 里有时有交叉信息
- **Apple Release Notes**：https://developer.apple.com/news/releases/ — 看 Dock/Mission Control 相关变更
- **OSXDaily / 9to5Mac**：第一时间报道 macOS beta 的可见变化，从用户角度帮你判断 Dock 功能是否有改动

***

## 十、调试中常见失败场景与处理方法

### 场景 A：`po $x0` 输出 `0x1` 或很小的数值

**原因**：frame #0 的 `$x0` 不是对象指针，而是布尔值、整数参数或枚举值。这是 C/C++/Swift 函数而非 ObjC method，第一个参数不是 `self`。

**处理流程**：

```bash
# Step 1：确认 $x0 到底是什么
(lldb) p/d $x0      # 打印十进制，看数值是否有业务意义
(lldb) p/x $x0      # 打印十六进制

# Step 2：检查后续参数寄存器是否有对象指针
(lldb) po (id)$x1
(lldb) po (id)$x2
(lldb) po (id)$x3

# Step 3：切到上层 frame，扫描 callee-saved 寄存器
(lldb) frame select 1
(lldb) po (id)$x19
(lldb) po (id)$x20
(lldb) po (id)$x21
(lldb) po (id)$x22

# Step 4：查看 frame #1 的反汇编，找调用前的寄存器准备
(lldb) dis -b -c 30     # 从当前 PC 反向看 30 条指令
# 找 "mov x0, w23" 这类把小整数传进去的指令
# 再往上找 w23 是从哪来的，可能就是控制字段
```

***

### 场景 B：断点命中，但 `bt` 调用栈里全是 `unnamed_symbol`

**原因**：Dock 是全量 stripped 的 binary，所有内部函数都没有名字。这是正常现象，不是你的问题。

**处理方法**：

靠 static offset 还原调用栈的静态地址：

```bash
# 已知：slide = 0x04374000，image_base = 0x100000000
# frame #1 显示地址 0x10459ebb8

# 计算静态 offset：
# static_offset = runtime_addr - image_base - slide
#              = 0x10459ebb8 - 0x100000000 - 0x04374000
#              = 0x00225BB8

# 然后在 Ghidra 里直接跳到 0x100225BB8 查看函数
```

**自动化脚本**（节省心智负担）：

```python
# 在 lldb Python 里运行
(lldb) script

slide = 0x04374000
image_base = 0x100000000

frames = [
    0x10459ebb8,
    0x10444bc118,
    # 从 bt 输出粘贴
]

for addr in frames:
    static = addr - image_base - slide
    print(f"runtime: {hex(addr)} → ghidra: {hex(image_base + static)}")
```

***

### 场景 C：Pattern 在 Python 脚本里找不到（0 个匹配）

原因有三种，按概率从高到低：

**原因 1：pattern 本身写错了**

```bash
# 验证方法：用一段肯定存在的极短序列先测试
python3 -c "
data = open('Dock_arm64e', 'rb').read()
# pacibsp 必然大量存在
count = data.count(bytes.fromhex('7F2303D5'))
print(f'pacibsp appears {count} times')
# 如果是 0，说明你搜索的文件根本不是目标 binary
"
```

**原因 2：`??` wildcard 没有被正确处理**

很多人直接把 `??` 当字面字节去 `.find()`，Python 的 `bytes.find()` 不支持 wildcard。必须用逐字节比对的方式：

```python
def pattern_match(data, pattern_str):
    parts = pattern_str.split()
    pat = [(None if p == '??' else int(p, 16)) for p in parts]
    for i in range(len(data) - len(pat)):
        if all(b is None or data[i+j] == b for j,b in enumerate(pat)):
            yield i
```

**原因 3：pattern 对应的函数在新版本里被完全重写**

这时候你的 pattern 确实失效了，需要从头定位。回到 Ghidra Version Tracking，找到旧函数的新位置，重新提取 pattern。

***

### 场景 D：pattern 搜索到多个匹配（误匹配）

pattern 太短或者太通用。处理策略：

**策略 1：加长 pattern 后缀**

往函数深处再取几条稳定指令，追加到 pattern 末尾：

```bash
# 在 Ghidra 里，当前 pattern 命中了两个位置
# 分别查看两个函数的后续指令
# 找到从第几条指令开始两者出现分叉
# 把那个分叉之前的稳定片段加入 pattern
```

**策略 2：收紧 wildcard**

把某些 `??` 改为更具体的值，前提是你验证过该字节在目标版本里是固定的：

```
# 例如 BL 的高字节如果总是 97（向后跳），可以写成 ?? ?? ?? 97
# 而不是 ?? ?? ?? 94（范围更大）
```

**策略 3：结合 offset 缩小搜索窗口**

在代码里限制搜索范围，让 offset 起到真正的筛选作用：

```c
// 只在 [offset - 0x50000, offset + 0x50000] 范围内搜索
// 即便 pattern 有歧义，在这个窗口内也不会匹配到别的函数
```

***

### 场景 E：`EXC_BAD_ACCESS` 崩溃，Dock 重启

**原因**：对无效地址做了 `po`/`x`，或者触发了不该触发的执行路径。你在 LLDB 里做表达式求值时，LLDB 实际上会在目标进程里执行这段代码，有真实的副作用。

**保护措施**：

```bash
# 设置求值超时，防止死锁
(lldb) settings set target.max-children-count 64
(lldb) settings set expression.timeout 5

# 优先用 p 而不是 po（p 不调用 ObjC description，更安全）
(lldb) p/x $x19     # 安全
(lldb) po $x19      # 可能触发 ObjC 方法，有风险

# 读内存优先用 x，完全不执行任何代码
(lldb) x/8xg $x19   # 最安全
```

**Dock 崩溃重启后的快速恢复**：

```bash
# Dock 重启后 PID 变了，ASLR 重新随机化，需要重新 attach
sudo lldb -p $(pgrep -x Dock)
(lldb) image list -o -f Dock   # 重新获取 slide
# 重新计算所有运行时地址
```

***

### 场景 F：在系统 beta 版本上无法 attach（SIP/AMFi 限制）

macOS beta 有时会加强 Hardened Runtime，导致 lldb 无法 attach 到系统进程：

```bash
# 错误：
# error: process attach failed: 'A' packet returned an error: 1

# 解法1：确认 SIP 已禁用
csrutil status
# 应该是 "System Integrity Protection status: disabled"

# 解法2：在 Recovery Mode 额外禁用 AMFi（Apple Mobile File Integrity）
nvram boot-args="amfi_get_out_of_my_way=1"

# 解法3：为调试的 binary 添加 get-task-allow entitlement（只适合自己签名的 binary）
# 不适用于 Dock，跳过

# 解法4：用 frida 代替 lldb（frida 绕过某些 attach 限制）
frida -n Dock --runtime=v8
```

***

### 场景 G：Ghidra decompiler 输出乱且充满 `undefined8`

这不是 Ghidra 的 bug，是因为 arm64e 带有 PAC 修饰的指令让 Ghidra 的类型推断困难。处理方法：

**手动添加类型标注**，让 decompiler 重新推断：

```
1. 右键目标函数 → Edit Function Signature
2. 将 param_1 改为 id（ObjC 对象）
3. 将 param_2 改为 SEL（ObjC selector）
4. Decompile 窗口自动刷新，伪代码立即变清晰

5. 如果是 C++ 类：
   DataType Manager → 手动创建一个 struct，按照你分析的 ivar layout 定义字段
   将 param_1 的类型改为 MyClass *
   Decompiler 随即把所有 *(param_1 + 0x70) 显示为 this->dppm
```

**在 Ghidra 里设置 arm64e PAC 感知**：

```
Edit → Options → Disassembler → 勾选 "Treat PAC instructions as NOP"
```

这样 `pacibsp`、`autibsp`、`retab` 这类指令不会干扰 Ghidra 的控制流分析。

***

## 十一、差分逆向：每次升级只需做最少的工作

这才是高手维护 pattern 的真正姿势——不是每次从零逆，而是做**差量分析**。

### 11.1 建立你自己的 Dock Reverse Map

把每次逆向的成果固定记录下来：

```markdown
## macOS 26.0 (Dock build XXXXX)
| 目标         | Static Offset | Pattern Hash | 动态验证时间 |
|-------------|--------------|-------------|------------|
| add_space   | 0x1f07d8     | sha256前8位  | 2026-01-10 |
| remove_space| 0x1e0000     | ...          | 2026-01-10 |
| dppm        | 0x70000      | ...          | 2026-01-10 |

## macOS 26.4 (Dock build YYYYY)
| 目标         | Static Offset | 变化类型         | 处理方式          |
|-------------|--------------|----------------|-----------------|
| add_space   | 0x1f05a0     | 栈帧 0x70→0x50  | 新增 26.4 分支    |
| remove_space| 0x1e0000     | 未变             | 无需操作          |
| dppm        | 0x70000      | offset 统一      | 删除 >=4 分支     |
```

### 11.2 差分 Pattern 识别的三种情形

**情形 1：只有 offset 变了，代码没变**

```bash
# Python 用旧 pattern 在新 binary 里搜索
python3 check_patterns.py Dock_arm64e_new

# 输出：✅ add_space: ['0x1f05a0']  ← offset 变了但 pattern 仍然命中
# 只需要更新 get_add_space_offset() 返回值
```

**情形 2：offset 和 pattern 都变了（函数被重编译）**

```bash
# Python 输出：❌ add_space: NOT FOUND

# 用 Version Tracking 找到新函数位置
# 对比新旧汇编，找差异字节
# 重写 get_add_space_pattern() 里的对应版本分支
```

**情形 3：函数被内联或合并（消失了）**

```bash
# Python 输出：❌ add_space: NOT FOUND
# Version Tracking 也找不到匹配

# 说明 Apple 把这个函数内联进了 caller
# 需要从调用链上移一层，找调用它的函数
# 并更新 yabai 的调用策略
```

### 11.3 快速 diff 脚本（两份 binary 的函数级比较）

```python
#!/usr/bin/env python3
"""
Quick function-level diff between two arm64e Dock binaries.
Identifies functions that changed code but kept similar size.
"""
import sys, struct

def find_functions(data):
    """Find all function entry points by looking for pacibsp."""
    PACIBSP = bytes.fromhex('7F2303D5')
    funcs = []
    idx = 0
    while True:
        pos = data.find(PACIBSP, idx)
        if pos == -1:
            break
        funcs.append(pos)
        idx = pos + 4
    return funcs

def extract_func_bytes(data, offset, size=128):
    """Extract first N bytes of a function as fingerprint."""
    return data[offset:offset+size]

def compare_binaries(old_path, new_path):
    with open(old_path, 'rb') as f:
        old = f.read()
    with open(new_path, 'rb') as f:
        new = f.read()
    
    old_funcs = find_functions(old)
    new_funcs = find_functions(new)
    
    print(f"Old: {len(old_funcs)} functions | New: {len(new_funcs)} functions")
    
    # Build fingerprint sets
    old_prints = {extract_func_bytes(old, o) for o in old_funcs}
    new_prints = {extract_func_bytes(new, o) for o in new_funcs}
    
    # Disappeared from old
    lost = old_prints - new_prints
    # New in new
    gained = new_prints - old_prints
    
    print(f"Changed/removed: {len(lost)} | New/modified: {len(gained)}")
    
    # Find offsets of changed functions in old binary
    for fp in list(lost)[:20]:  # Show first 20
        for off in old_funcs:
            if extract_func_bytes(old, off) == fp:
                print(f"  Changed function at old offset: {hex(off)}")
                break

if __name__ == "__main__":
    compare_binaries(sys.argv[1], sys.argv[2])
```

***

## 十二、ARM64 指令手册速查：Pattern 编写参考卡

这张速查表，日后编写/修改 pattern 时可以直接翻：

### 12.1 常见指令的机器码特征

| 指令 | 典型机器码 | Pattern 写法 | 备注 |
|------|-----------|------------|------|
| `pacibsp` | `7F 23 03 D5` | 全固定 | 几乎所有函数入口 |
| `retab` | `FF 0F 5F D6` | 全固定 | 函数出口 |
| `sub sp, sp, #N` | `FF ?? ?? D1` | `FF ?? ?? D1` | N 变则中间两字节变 |
| `stp x29, x30, [sp,#N]` | `FD ?? ?? A9` | `FD ?? ?? A9` | N 变则中间字节变 |
| `add x29, sp, #N` | `FD ?? ?? 91` | `FD ?? ?? 91` | N 同 stp 一致 |
| `mov x0, x19` | `E0 03 13 AA` | 全固定 | 常见参数传递 |
| `mov x1, x30` | `E1 03 1E AA` | 全固定 | 保存 LR 到参数寄存器 |
| `mov x30, x1` | `FE 03 01 AA` | 全固定 | 恢复 LR |
| `bl <addr>` | `?? ?? ?? 94~97` | `?? ?? ?? 94` | 偏移总变 |
| `blr x16` | `00 02 3F D6` | 全固定 | 通过寄存器跳转 |
| `ldr x0, [x8]` | `00 01 40 F9` | 全固定 | 从 x8 加载指针 |
| `ldr x0, [x0, #0x70]` | `00 1C 40 F9` | 全固定（偏移 0x70） | ivar 偏移固定时可用 |
| `cbz x0, #offset` | `?? ?? ?? B4` | `?? ?? ?? B4` | 跳转偏移变 |
| `adrp xN, #page` | `?? ?? ?? 90` | `?? ?? ?? 90` | 页地址总变 |
| `add xN, xN, #off` | `?? ?? ?? 91` | `?? ?? ?? 91` | 页内偏移总变 |
| `objc_retain call` | `?? ?? ?? 94` 前 `mov x0, ...` | 配合 stub 识别 | |
| `objc_release call` | 同上 | | |

### 12.2 STP 指令的偏移编码规律

```
stp x29, x30, [sp, #N]  的机器码：

FD 7B [offset_byte] A9

offset_byte 与 N 的关系（8字节对齐，用 0x?000 的 N）：
  N = 0x00  → offset_byte = 00
  N = 0x10  → offset_byte = 01
  N = 0x20  → offset_byte = 02
  N = 0x30  → offset_byte = 03
  N = 0x40  → offset_byte = 04
  N = 0x50  → offset_byte = 05   ← macOS 26.4 add_space 用的
  N = 0x60  → offset_byte = 06   ← macOS 26.0 add_space 用的
  N = 0x70  → offset_byte = 07
  N = 0x80  → offset_byte = 08
  ...以此类推（offset_byte = N / 0x10）
```

所以当 pattern 里有 `FD 7B 05 A9` vs `FD 7B 06 A9`，就是栈帧从 0x60 变到 0x50 的直接体现。

### 12.3 BL 指令偏移的方向判断

```
97 结尾 = 向后跳（调用地址 < 当前地址，偏移为负数）
94/95 结尾 = 向前跳（调用地址 > 当前地址，偏移为正数）

asmvik 的 pattern：48 89 FC 97
97 结尾 → 这是向后跳的 BL
FC 88 48 → 26 bit 偏移（小端序），解码：
  sign-extend(0x3FC8848 * 4) = 0xFF32_1120（一个较大的负数偏移）
  说明目标函数在当前函数的「之前」很远的位置

这意味着这个 BL 调用了一个位于 Dock binary 更低地址的函数
```

***

## 十三、逆向完成后：如何维护 yabai 的 Pattern 代码

### 13.1 `arm64_payload.m` 的结构设计原则

yabai 每个 pattern 函数遵循同一个约定：

```c
const char *get_xxx_pattern(NSOperatingSystemVersion os_version) {
    if (os_version.majorVersion == 26) {
        // 精细到 minorVersion 才分支，大多数情况下不用分
        if (os_version.minorVersion >= 4) {
            return "新 pattern";
        }
        return "26.0 pattern";
    } else if (os_version.majorVersion == 15) {
        return "Sequoia pattern";
    }
    // ...
    return NULL;
}
```

**设计原则**：

- **不要过早分 minorVersion**。只有在两个 minor 版本之间 pattern 真的不同时才分支，否则保持简单
- **minorVersion 条件用 `>= N` 而不是 `== N`**，因为后续版本往往沿用同一 pattern，用 `==` 会导致新版本 fall through 到错误分支
- **每次新增分支都加注释说明从哪里得来**，asmvik 的那几行注释就是最好的示例

### 13.2 给新 pattern 写测试（本地验证）

yabai 没有单元测试框架，但你可以在本地跑一个独立验证脚本：

```python
#!/usr/bin/env python3
"""Validate yabai patterns against local Dock binary."""

import os, subprocess

DOCK_PATH = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
SLICE_PATH = "/tmp/Dock_arm64e"

# Extract arm64e slice
subprocess.run(["lipo", "-thin", "arm64e", DOCK_PATH, "-output", SLICE_PATH], check=True)

with open(SLICE_PATH, 'rb') as f:
    data = f.read()

# Offsets and patterns for macOS 26.4
import platform
ver = platform.mac_ver()[0]
minor = int(ver.split('.')[1]) if '.' in ver else 0

PATTERNS = {
    "add_space_offset": 0x250000,
    "add_space_26_4": "7F 23 03 D5 E1 03 1E AA 48 89 FC 97 FE 03 01 AA FD 7B 05 A9 FD 43 01 91 F3 03",
    # 添加其余 pattern...
}

def match(data, offset, pattern_str, window=0x80000):
    parts = pattern_str.split()
    pat = [(None if p=='??' else int(p,16)) for p in parts]
    start = max(0, offset - window)
    end   = min(len(data), offset + window)
    for i in range(start, end - len(pat)):
        if all(b is None or data[i+j]==b for j,b in enumerate(pat)):
            yield i

results = list(match(data, PATTERNS["add_space_offset"], PATTERNS["add_space_26_4"]))
if len(results) == 1:
    print(f"✅ add_space 26.4: offset=0x{results[0]:X}")
elif len(results) == 0:
    print("❌ add_space 26.4: NOT FOUND — pattern needs update")
else:
    print(f"⚠️  add_space 26.4: AMBIGUOUS — {len(results)} matches: {[hex(r) for r in results]}")
```

### 13.3 何时应该放弃 pattern，改用更高层的 API

pattern 匹配是一种脆弱的方法，有时候更好的选择是：

- **CGSPrivate API**：CoreGraphics Server 暴露了一些 semi-public 的 CGS 函数，比 Dock 内部 pattern 更稳定
- **Accessibility API**：Mission Control 的部分操作可以通过 `AXUIElement` 触达，不需要 inject 进 Dock
- **AppleScript / JXA**：Dock 支持有限的 scripting，某些空间操作可以用脚本调用
- **私有 Framework XPC**：`SkyLight.framework`、`DockKit` 等私有框架有 XPC 接口，有时比 pattern 更稳

当某个 pattern 在连续三个 macOS 版本里都需要修改，就该认真考虑是否有替代路径。

***

## 十四、学习路线图：如何成为能独立逆向的人

### 阶段一：建立基础（2~4 周）

- 🔲 把 ARM64 调用约定背下来（ABI 文档：AAPCS64）
- 🔲 用 Ghidra 把一个你熟悉的开源 macOS App（带符号）反编译，对照源码理解 decompiler 的输出
- 🔲 用 LLDB attach 到一个简单 app，练习 `bt`、`frame select`、`po`、`x/xg`
- 🔲 手动解码 5 条 ARM64 指令（查 ARM Architecture Reference Manual）

### 阶段二：进入实战（1~2 个月）

- 🔲 用 Ghidra Version Tracking 对比同一 App 的两个相邻版本
- 🔲 用 Frida hook 一个 App 的 ObjC 方法，打印参数和返回值
- 🔲 在 Dock 里用 LLDB 完成一次完整的"触发 → 断点 → 对象图穿透"流程
- 🔲 为一个已知的 yabai pattern 写一个 Python 验证脚本，在本地 binary 里跑通

### 阶段三：独立维护（持续）

- 🔲 每次 macOS beta 发布，主动跑一次 `check_patterns.py`，记录结果
- 🔲 遇到 pattern 失效时，独立完成定位、验证、更新、测试全流程
- 🔲 建立自己的 Dock Reverse Map（本文十一节的表格格式）
- 🔲 开始给 yabai 提交 pattern 修复的 PR

### 必读资料

| 资料 | 用途 |
|------|------|
| **ARM Architecture Reference Manual (ARMv8-A)** | 权威指令手册，查机器码 |
| **AAPCS64** | ARM 64位调用约定官方文档 |
| **Ghidra Documentation** | Version Tracking、Script API |
| **Apple Open Source (XNU kernel)** | https://opensource.apple.com，理解 Mach/XPC |
| **frida-gum API docs** | Interceptor、Memory API |
| **iphonedev.wiki / theiphonewiki** | 虽然以 iOS 为主，但 macOS 私有 API 信息也在这里 |
| **objc.io 文章合集** | 理解 ObjC runtime 内部结构 |
| **reverseengineering.stackexchange.com** | 实际问题的社区经验 |