# 🔬 完整技术报告：macOS 26 Space 创建的完整推理与工程历程

***

## 第一幕：真正的问题是什么

一开始我们面对的不是"如何适配新版本"这种宽泛的工程问题，而是一个非常具体的症状：

> **`yabai -m space --create` 在 macOS 26 上导致 Dock 崩溃，崩溃地址是 `0x1`。**

`0x1` 这个地址是典型的"把整数 `1` 当指针解引用"的 EXC_BAD_ACCESS。不是栈溢出，不是 use-after-free，是在用一个根本不是地址的值做内存访问。这个线索至关重要——它暗示有某个地方把布尔值 `true`（整数 `1`）错误地当成了对象指针。

***

## 第二幕：LLDB attach，找到崩溃的真实现场

我们用 LLDB attach 到 Dock，ASLR slide 为 `0x04374000`：

```
[0] 0x0000000004374000  /System/.../Dock.app/.../Dock
```

pattern scan 找到的 `addSpace` 函数入口（含 slide）是 `0x1045647D8`。在这里打断点，然后在 Mission Control 里手动点击 `+` 触发：

```
frame 0: 0x1045647d8  <unnamed>
  pacibsp                        ; ARM64e PAC signed entry
  stp x22, x21, [sp, #-0x30]!
  stp x20, x19, [sp, #0x10]     ; 保存 x20, x19（callee-saved）
  stp x29, x30, [sp, #0x20]
```

此时检查寄存器：

```
lldb> p $x0
unsigned long = 0x0000000000000001
```

**`x0 = 1`**。这不是一个对象。接着看 frame 1 的调用现场：

```asm
; frame 1（调用方）的关键几行：
0x10459eb98 <+68>:  mov  x19, x20          ; x19 = 调用方的 self（callee-saved）
0x10459ebb4 <+96>:  bl   0x1045647d8       ; 调用 addSpace，此时 x0 = Bool
; 在 bl 之前：
0x10459ebb0 <+92>:  mov  x0, x23           ; x23 = ldr w23,[x20,#0x38] 读出来的 Bool
0x10459ebb4 <+96>:  bl   0x1045647d8
```

`x23` 是从 `x20 + 0x38` 处加载的一个 word——是 `Bool animate`，值为 `true`（`1`）。**这个函数的第一个参数根本就不是 ManagedSpace 对象，而是 `Bool isUserClicked`。**

旧的理解是：
- `x0` = `new ManagedSpace()`
- `x20` = `DisplaySpace`（显式参数）

macOS 26 的实际签名是：

```swift
// macOS 26 Tahoe: Swift method on SpacesBarWindowController
func addSpace(isUserClicked: Bool)
//   x0 = Bool (true/false)
//   x20 = Swift self (由 caller 填入，callee-saved 寄存器)
//   ManagedSpace 在函数内部 alloc
//   DisplaySpace 从 global dock_spaces 推断
```

这解释了 `0x1` 崩溃：旧代码把 `ManagedSpace` 指针放进 `x0`，函数把它当 `Bool` 读（其实无所谓），但同时 `x20` 里被放了 `DisplaySpace` 对象而不是正确的 `self`，导致函数访问 `self + 某偏移` 时拿到了 `0x1`，解引用崩溃。

***

## 第三幕：x20 到底是什么——callee-saved 的双重身份

这里有一个 ARM64 调用约定的微妙点。`x19`–`x28` 是 **callee-saved**，被调用方（callee）在 prologue 里 `stp` 保存、在 epilogue 里 `ldp` 恢复。但在 `bl` 执行之前，调用方（caller）可以把**任何值**放进这些寄存器，callee 保存的是调用方当时寄存器里的内容，然后在函数体内可以复用这个槽位。

对于 Swift 编译器生成的代码，**调用方 frame 1 在 `bl` 之前，`x20` 里持有的是 frame 1 的 Swift `self`**（`SpacesBarWindowController`）。frame 0（`addSpace`）的 prologue 把 x20 存入栈，然后在函数体内可以通过这个栈槽间接访问 frame 1 的 `self`，进而访问它持有的 `dock_spaces`。这是 Swift 编译器实现"隐式 self 捕获"的方式——不通过显式参数，通过 callee-saved 寄存器的传递。

换句话说：`x20 = DisplaySpace`（旧 macOS 15 做法）是把 `x20` 作为**函数参数**使用；`x20 = caller's Swift self`（macOS 26 做法）是把 `x20` 作为**调用上下文的隐式捕获**使用。Apple 在 macOS 26 里把 DisplaySpace 的查找逻辑内化进了函数本身，旧的显式参数风格被彻底替换。

***

## 第四幕：第一次尝试——直接调用 `space_create_entry`

了解了 ABI 之后，最直觉的尝试是：既然函数需要 `x0 = display_id`（`int32_t`）和 `x20 = Spaces singleton`（Swift `self`），那我们找到 `Spaces` 单例，填好寄存器，直接调用。

### Phase 27：地址重复计算的 bug

最初的代码是这样的：

```c
// ❌ 错误写法：
uint64_t space_create_addr = base_addr + image_slide_val + 0x1f07d8ULL;
```

**问题**：`static_base_address()` 返回的已经是加了 slide 的运行时地址，`image_slide()` 也是 slide 值，两个加在一起等于把 slide 加了两遍。函数指针跳到了错误的地址，直接 crash。

修复：`init_instances()` 里已经通过 `hexfindseq` 算好了 `space_create_entry_fp`，直接用：

```c
// ✅ 正确写法：
uint64_t space_create_addr = space_create_entry_fp;  // 已在 init_instances 预计算
```

同时，读取 Spaces 单例的地址也从错误的 offset 修正为通过 LLDB 反汇编 `adrp/add` 指令序列手动 decode 出来的 `0x488028`：

```c
uint64_t baseaddr = static_base_address() + image_slide();
uintptr_t spaces_global_ptr = baseaddr + 0x488028ULL;
id spaces_singleton = *(id *)spaces_global_ptr;
```

`0x488028` 的来源：frame 1 的反汇编里有 `adrp x25, #X` + `add x25, x25, #Y` 指令对，`decode_adrp_add()` 函数把这两条指令解码成绝对地址，减去 slide 就是文件偏移 `0x488028`。

### Phase 28：函数仍然崩溃——retain 缺失

修正地址后，日志打出来了：

```
[SPACE] singleton=0xc00870480 func=0x104c787d8
```

地址都对，但函数一调用还是崩。这时候仔细看了 frame 1 的反汇编，发现调用方在 `bl` 之前有：

```asm
0x10459eba8 <+84>:  bl   objc_retain    ; ← 对 singleton 做 retain
0x10459ebac <+88>:  mov  x20, x0        ; ← retained 的结果放进 x20
0x10459ebb0 <+92>:  mov  x0, x23        ; ← x0 换成 Bool
0x10459ebb4 <+96>:  bl   <addSpace>
```

原生调用在 `bl` 之前做了 `objc_retain`，然后把 retained 的指针放进 `x20`。我们的代码直接传了原始指针，没有 retain，导致 Swift 的 ARC 引用计数逻辑在函数内部操作了一个不该被减引用的对象。

### Phase 29：宏重写——原子 `asm volatile` + `blr` + retain/release

这是整个工程里最精细的一步。之前的宏把"设置寄存器"和"调用函数"分成了两个独立操作：

```c
// ❌ 旧宏（分离写法，编译器可以在中间插入指令）：
#define asm__call_add_space(v0, v1, func) \
    __asm__("mov x0, %0\n" "mov x20, %1\n" : : "r"(v0), "r"(v1) : "x0", "x20"); \
    ((void (*)())(func))();
```

这里有两个严重问题：
- **编译器可以在 `__asm__` 和 `((void (*)())(func))()` 之间插入任何指令**，修改 x0/x20 的值
- `((void (*)())(func))()` 是 C 函数调用，会通过 `bl` 跳转到一个**经过 PAC 认证的固定地址**，而 `space_create_entry_fp` 是运行时变量，必须用 `blr`（寄存器间接跳转）

新宏把所有操作合并进单一 `asm volatile` 块：

```c
// ✅ 新宏：原子块，编译器无法插入中间指令
#define asm__call_space_create_tahoe(display_id, spaces_self, func)     \
    do {                                                                  \
        __asm__ volatile (                                                \
            "mov w0, %w[did]\n"      /* x0 = display_id (int32_t) */    \
            "mov x20, %[self]\n"     /* x20 = Spaces singleton (Swift self) */ \
            "blr %[fp]\n"            /* indirect branch through register */ \
            :                                                            \
            : [did]  "r" ((uint32_t)(display_id)),                       \
              [self] "r" ((uintptr_t)(spaces_self)),                     \
              [fp]   "r" ((uintptr_t)(func))                            \
            : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7",         \
              "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",    \
              "x16", "x17", "x19", "x20", "x30", "memory"              \
        );                                                               \
    } while(0)
```

几个细节：

**① `"mov w0, %w[did]"` 而不是 `"mov x0, ..."`：** `display_id` 是 `uint32_t`，用 `w0`（32 位寄存器）写入，高 32 位自动清零。如果用 `x0`，约束器可能做符号扩展，导致高位非零，Swift 侧读到错误值。

**② `blr` 而不是 `bl`：** `bl` 是 PC 相对跳转，目标地址必须在编译期确定，编译器会生成带 PAC 的跳转序列。`blr` 是寄存器间接跳转，从寄存器里取地址，适用于运行时确定的函数指针。`space_create_entry_fp` 是运行时计算的变量，只能用 `blr`。

**③ clobber 列表包含所有 caller-saved 寄存器 + x30：** `x0`–`x17` 是 caller-saved（被调用方可以随意修改），`x30` 是链接寄存器（`blr` 会修改它）。如果不列进 clobber，编译器可能认为这些寄存器在调用前后不变，把某些值缓存在里面，导致后续逻辑读到被 callee 破坏的值。

**④ `"memory"` clobber：** 告诉编译器这个 asm 块可能读写任意内存位置，强制把所有挂起的内存写操作 flush，防止 store-load 重排序破坏 Swift ARC 的引用计数操作。

在调用侧：

```c
// 镜像原生调用：先 retain，用完 release
id retained = [spaces_singleton retain];
CGDirectDisplayID display_id = CGMainDisplayID();

NSLog(@"[yabai-sa][SPACE] calling space_create_entry(display_id=%u) retained=%p",
      display_id, (void *)retained);

dispatch_sync(dispatch_get_main_queue(), ^{
    asm__call_space_create_tahoe((uint32_t)display_id, retained, space_create_addr);
});

[retained release];
```

`dispatch_sync(main_queue)` 的包裹是因为 Dock 的 Spaces 状态全部在主线程上维护（NSRunLoop 驱动），在主线程之外修改会触发 thread sanitizer 或竞争条件。

### Phase 30：历史性成功 🎉

```
[SPACE] singleton=0xc00870480 func=0x104c787d8
[SPACE] calling space_create_entry(display_id=1) retained=0xc00870480
[SPACE] space_create_entry returned    ← 第一次成功返回！
```

Dock 没有崩溃，Mission Control 出现了新 Space。**这是第一次成功调用 `0x1f07d8` 且进程存活。**

***

## 第五幕：多显示器——IOKit 沙箱陷阱

成功之后立刻暴露了下一个问题：Space 永远创建在主显示器，无论 `yabai -m space --create` 是在哪个 display 的 Space 上下文里执行的。

原因是：

```c
CGDirectDisplayID display_id = CGMainDisplayID();  // ← 硬编码主显示器
```

修复思路是：从 `SLSCopyManagedDisplayForSpace` 拿到的 `display_uuid`（`CFStringRef`），反向查找它对应的 `CGDirectDisplayID`。

### 第一次尝试：IOKit

```c
// ❌ 失败：IOKit 在 Dock 沙箱下静默失败
#include <IOKit/IOKitLib.h>

static CGDirectDisplayID display_id_for_uuid(CFStringRef display_uuid) {
    uint32_t count = 0;
    CGGetActiveDisplayList(0, NULL, &count);
    CGDirectDisplayID displays[count];
    CGGetActiveDisplayList(count, displays, &count);

    for (uint32_t i = 0; i < count; i++) {
        io_service_t service = CGDisplayIOServicePort(displays[i]);
        // ↑ 在 Dock 沙箱里返回 MACH_PORT_NULL (0)，不报错，静默失败

        if (!service) continue;

        CFTypeRef uuid_ref = IORegistryEntryCreateCFProperty(
            service,
            CFSTR("IODisplayUUID"),
            kCFAllocatorDefault, 0
        );
        // ↑ service = 0，这里也静默返回 NULL
        // ...
    }
    // 永远 fallback 到 CGMainDisplayID()
    return CGMainDisplayID();
}
```

**陷阱的本质**：`CGDisplayIOServicePort()` 在 macOS 12+ 已被标记为 deprecated，但在普通进程里还能工作。**Dock 是沙箱进程**，沙箱 profile 限制了对 IOKit Mach 服务的访问，`IOServiceGetMatchingService` 系列调用返回 `MACH_PORT_NULL` 而不是报错。这种静默失败极难发现——代码逻辑完全正确，只是每次都 fallback。

如果不实际在 Dock 沙箱里运行一遍，几乎无法预料这个问题。

### 修复：`CGDisplayCreateUUIDFromDisplayID`

```c
// ✅ 正确：纯 CoreGraphics API，沙箱可用
// 声明（不在公开头文件里，需要手动声明）
extern CFUUIDRef CGDisplayCreateUUIDFromDisplayID(uint32_t did);

static CGDirectDisplayID display_id_for_uuid(CFStringRef display_uuid)
{
    uint32_t display_count = 0;
    CGGetActiveDisplayList(0, NULL, &display_count);
    if (display_count == 0) return CGMainDisplayID();

    CGDirectDisplayID displays[display_count];
    CGGetActiveDisplayList(display_count, displays, &display_count);

    for (uint32_t i = 0; i < display_count; i++) {
        // CoreGraphics UUID API: CGDirectDisplayID → CFUUIDRef
        // Works in Dock sandbox (no IOKit required)
        CFUUIDRef uuid_ref = CGDisplayCreateUUIDFromDisplayID(displays[i]);
        if (!uuid_ref) continue;

        // Convert CFUUIDRef to CFStringRef for comparison
        CFStringRef uuid_str = CFUUIDCreateString(kCFAllocatorDefault, uuid_ref);
        CFRelease(uuid_ref);
        if (!uuid_str) continue;

        bool match = CFEqual(uuid_str, display_uuid);
        CFRelease(uuid_str);

        if (match) return displays[i];
    }

    NSLog(@"[yabai-sa][SPACE] WARNING: no display matched UUID, falling back to main display");
    return CGMainDisplayID();
}
```

`CGDisplayCreateUUIDFromDisplayID` 为什么能在沙箱里工作？因为它不走 IOKit Mach port，它直接查询 CoreGraphics Server（WindowServer）维护的 display 信息表——这是同进程内的共享内存或私有 SPI，不需要跨越 Mach port 边界，沙箱 profile 不拦截它。

使用侧：

```c
// 用 display_uuid（来自 SLSCopyManagedDisplayForSpace）反查 display_id
CGDirectDisplayID display_id = display_id_for_uuid(display_uuid);
// 不再硬编码 CGMainDisplayID()
```

同时清理了 Makefile 里错误引入的 `-framework IOKit`（IOKit 沙箱下不可用，引入只会误导未来的维护者）。

***

## 最终架构：完整调用流水线

```
yabai -m space --create
         │
         ▼  (unix domain socket → daemon thread)
do_space_create(message)
         │
         ├─ unpack: space_id (当前 space 用于确定 display)
         │
         ├─ SLSCopyManagedDisplayForSpace()
         │     └─→ display_uuid: CFStringRef  ("37D8832A-...")
         │
         ├─ display_id_for_uuid(display_uuid)  ← 多显示器修复
         │     ├─ CGGetActiveDisplayList() → 枚举所有 display
         │     └─ CGDisplayCreateUUIDFromDisplayID(each)
         │           ├─ CFUUIDCreateString() → 比较
         │           └─ CFEqual() 匹配 → return CGDirectDisplayID
         │
         ├─ 读取 Spaces 单例
         │     └─ *(id *)(baseaddr + 0x488028)
         │           └─ 通过 LLDB adrp/add decode 确定 offset
         │
         ├─ [spaces_singleton retain]  ← 镜像原生调用约定
         │
         ├─ dispatch_sync(main_queue) {
         │     asm__call_space_create_tahoe(
         │         display_id,      // w0: int32_t
         │         retained,        // x20: Swift self (Spaces singleton)
         │         space_create_entry_fp  // blr 间接跳转
         │     )
         │     /* 原子块：mov w0 / mov x20 / blr 不可分割 */
         │   }
         │
         ├─ [retained release]
         │
         └─ CFRelease(display_uuid)
```

***

## 深度比较：旧路径 vs 新路径的每一个维度

| 维度 | macOS 12–15 旧路径 | macOS 26 新路径 |
|------|------|------|
| **Pattern 返回值** | 有效字节序列，`hexfindseq` 找函数 | 返回 `NULL`，`addspacefp == 0` 为信号 |
| **函数指针获取** | `hexfindseq` scan → `ptrauth_sign` | 同样 `hexfindseq`，目标是 `space_create_entry_fp` |
| **x0 语义** | `ManagedSpace *` 对象 | `Bool isUserClicked`（`int32_t 1`） |
| **x20 语义** | `DisplaySpace *` 显式参数 | 调用方的 Swift `self`（Spaces 单例） |
| **ManagedSpace 来源** | 外部 alloc，传入 x0 | 函数内部 alloc（我们完全不管） |
| **DisplaySpace 查找** | x20 显式传入 | 函数内部从 `dock_spaces` global 推断 |
| **调用宏** | `asm + ((void(*)())fp)()` 分两步 | 单一 `asm volatile` 块，`blr` 间接跳转 |
| **retain/release** | 无 | 有，镜像原生 frame 1 的 `objc_retain` |
| **display 定位** | 无需，传 DisplaySpace 对象即可 | `CGDisplayCreateUUIDFromDisplayID` 反查，绕过 IOKit 沙箱 |
| **clobber 列表** | `"x0", "x20"` 仅两个 | 全部 caller-saved (`x0`–`x17`) + `x30` + `memory` |
| **Pattern 体系改动** | N/A | 零改动，`NULL` 作信号即可 |
| **崩溃风险点** | ABI 误解（macOS 26 x0/x20 语义变了） | offset `0x488028` 如 Dock 更新则需重新 decode |
| **多显示器支持** | DisplaySpace 里直接有 display 信息 | `display_id_for_uuid()` 辅助函数，纯 CG API |
| **沙箱兼容性** | 无沙箱相关代码 | 排除 IOKit，只用 CoreGraphics SPI |

***

## 为什么 `blr` + 原子 `asm volatile` 是关键

这是整个方案里最容易被低估的工程细节，值得单独展开。

假设用分离写法：

```c
__asm__("mov x0, %0\nmov x20, %1\n" : : "r"(v0), "r"(v1) : "x0", "x20");
((void (*)())(func))();
```

编译器看到这是两个独立的语句。在 `-O2` 下，它完全有权利在这两条语句之间插入：
- ARC 插入的 `objc_release(something)`（破坏 x0/x20）
- 某个局部变量的 spill/reload（通过 x0/x1 做内存访问）
- 内联展开的辅助函数（破坏任意 caller-saved 寄存器）

更严重的是 `((void (*)())(func))()` 这个 C 函数调用语法：编译器生成的是 `bl <PAC signed address>`，而 `func` 是一个 `uint64_t` 变量，不是编译期已知的符号地址。在 arm64e 上，对任意运行时地址做 `bl` 需要先经过 `ptrauth_sign`，否则 CPU 的 PAC 认证会失败（`SIGILL`）。`blr` 则直接把寄存器里的值当地址跳转，由调用方（我们）负责这个地址的合法性——而 `space_create_entry_fp` 已经通过 `ptrauth_sign_unauthenticated(addr, ptrauth_key_asia, 0)` 签好了，完全合法。

单一 `asm volatile` 块保证了三件事，每一件都是独立的正确性保证，不是可以随便省略的。

***

**第一：编译器不能在 `mov w0 / mov x20 / blr` 三条指令之间插入任何内容。**

GCC/Clang 的内联汇编有一个关键规则：**单个 `asm` 语句的内部指令序列是原子的**，编译器不会在其中插入任何生成代码。但如果你把设置寄存器和调用函数分成两个语句，编译器就完全自由了。在 `-O2` 下它有权在这两条语句之间调度任何操作——ARC 自动插入的 `objc_release`、局部变量的 spill/reload、内联展开后的辅助代码，全都可能落在这个缝隙里，悄悄修改 `x0` 或 `x20` 的值。合并成一个 `asm volatile` 块，这个缝隙就不存在了。

***

**第二：`volatile` 防止整个块被优化掉。**

不带 `volatile` 的 `asm` 语句，如果编译器通过数据流分析判断它的输出没有被使用（no output constraints），就可以直接删除整个语句。`blr` 跳转没有 C 级别的返回值，编译器可能认为这是"死代码"。加上 `volatile`，编译器就必须无条件保留这个块，因为它声明了可能有观察到的副作用（side effects），编译器不能证明删掉它是安全的。

***

**第三：`"memory"` clobber 在调用前后建立完整的编译器内存屏障。**

这里有一个常见的误解：`"memory"` clobber 不是硬件内存屏障（不等于 `dmb ish`），它是**编译器屏障**。它告诉编译器：这个 asm 块可能读写任意内存位置，所以：
- **屏障之前**：所有挂起的内存写操作必须在进入 asm 前真正写入内存（不能还留在寄存器里或被延迟）
- **屏障之后**：编译器不能把 asm 之后的内存读取提前到 asm 之前（因为不知道 asm 改了什么）

对我们的场景，这有两个直接作用。其一，`retained`（`objc_retain` 的返回值）是通过 ARC 管理的对象指针，在调用前它的引用计数必须真实地写入内存，Swift 的 ARC runtime 在函数内部会读取并操作这个计数器。如果没有 `memory` clobber，编译器可能把这个写操作缓存在寄存器里，函数内部读到的是旧的引用计数值，ARC 的 retain/release 配对就破了。其二，`blr` 之后，Swift 函数对 `dock_spaces` 全局状态做了修改（新 Space 被 append 进数组），后续代码需要读到这些修改。没有 `memory` clobber，编译器可能认为 asm 不影响这些变量，把之前缓存的旧值继续拿来用。

***

**clobber 列表的完整性为什么重要**

最后说 clobber 列表本身。我们列的是：

```c
: "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7",
  "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
  "x16", "x17", "x19", "x20", "x30", "memory"
```

`x0`–`x17` 是 ARM64 ABI 里的 caller-saved 寄存器，被调用方（`space_create_entry`）可以不保存直接覆盖。如果不把它们全部列进 clobber，编译器可能在 `blr` 前把某个临时值放进 `x3`，然后在 `blr` 后假设 `x3` 还是原来的值——但被调用的 Swift 函数早就把 `x3` 当临时寄存器用了，这个值已经不存在了。

`x30` 是链接寄存器（LR），`blr` 指令执行时会把返回地址写入 `x30`，同时跳转目标函数的 prologue（`pacibsp`）会做 PAC 验证。如果不声明 `x30` 被 clobber，编译器可能在 `blr` 之后还尝试从 `x30` 读调用方的返回地址——但这时候 `x30` 已经存了被调用函数执行期间写入的内容，读出来的是垃圾值。

注意 `x18` 没有列进去——这是 Apple 平台保留给内核使用的，用户态代码不应该接触它，不需要声明。`x19` 列进去是因为虽然它是 callee-saved，但 Swift 的 ARC 代码有时会在内部临时使用它做对象传递（`mov x19, x20` 这种 pattern 在 frame 1 里就出现过），声明它被 clobber 是防止编译器假设 `x19` 跨调用不变。


# 🔬 两种解法的深度对比：同一个问题，完全不同的哲学

***

## 先把两种解法的本质讲清楚

这个 commit（[731b3df](https://github.com/AhogeK/yabai/commit/731b3df62e823f7f7cf59abfe44a36c1a251e5f6)）是 **asmvik**（yabai 的原维护者 Åsmund Vikane）在 2026-03-29 11:10 提交的，针对 macOS 26.4 Apple Silicon。**总改动 8 行**（含 CHANGELOG），但涉及两个独立的 pattern 函数，每一处都有精确的技术含义。

我们的解法在同一天（2026-03-29）完成，但方向完全不同：不信任任何现有的函数入口，从 LLDB 崩溃现场往回推导，最终走了一条完全绕开 pattern 体系的 ObjC runtime 路径。

***

## asmvik 的两处改动：完整解剖

### 改动一：`get_add_space_pattern` 的 26.4 分支

```c
const char *get_add_space_pattern(NSOperatingSystemVersion os_version) {
    if (os_version.majorVersion == 26) {
        if (os_version.minorVersion >= 4) {
            // macOS 26.4: Xcode 16.3+ recompiled Dock, prologue changed
            return "7F 23 03 D5 E1 03 1E AA 48 89 FC 97 FE 03 01 AA FD 7B 05 A9 FD 43 01 91 F3 03";
        }
        // 26.0–26.3: same as macOS 15
        return "7F 23 03 D5 FF C3 01 D1 E1 03 1E AA ?? ?? 00 94 FE 03 01 AA FD 7B 06 A9 FD 83 01 91 F3 03";
    }
    // ...
}
```

逐字节对比两个 pattern，差异非常清晰：

**macOS 26.0–26.3（与 macOS 15 相同）：**

```
7F 23 03 D5   →  pacibsp                      ; ARM64e PAC 签名
FF C3 01 D1   →  sub sp, sp, #0x70            ; ← 立即预分配 112 字节栈帧
E1 03 1E AA   →  mov x1, x30                  ; 保存 LR 到 x1
?? ?? 00 94   →  bl  <_swift_retain 或 alloc> ; 调用辅助函数
FE 03 01 AA   →  mov x30, x1                  ; 恢复 LR
FD 7B 06 A9   →  stp x29, x30, [sp, #0x60]   ; 建立 frame pointer
FD 83 01 91   →  add x29, sp, #0x60
F3 03 ...     →  保存 callee-saved 寄存器
```

**macOS 26.4（新）：**

```
7F 23 03 D5   →  pacibsp                      ; 不变
              ←  「sub sp, sp, #0x70」消失了！
E1 03 1E AA   →  mov x1, x30                  ; 保存 LR 到 x1（位置前移）
48 89 FC 97   →  bl  <固定地址的辅助函数>      ; 注意：不再是 ?? 通配，是确定的 48 89 FC 97
FE 03 01 AA   →  mov x30, x1                  ; 恢复 LR
FD 7B 05 A9   →  stp x29, x30, [sp, #0x50]   ; ← 栈偏移从 0x60 变成了 0x50
FD 43 01 91   →  add x29, sp, #0x50
F3 03 ...     →  后续不变
```

两个关键变化：

**① `sub sp, sp, #0x70` 从 prologue 里消失了。** 这是 Xcode 16.3+ 引入的 ARM64e 新优化——"deferred stack allocation"（延迟栈帧分配）。编译器不在函数入口预分配整块栈空间，而是在第一次真正需要使用栈的时候才分配。好处是如果函数走了一条不需要保存 callee-saved 的快速路径，就完全省掉了这次 `sub sp`。这导致 26.0 的 pattern 在 26.4 的 Dock 里根本扫不到——pattern 的前几个字节在 26.4 里对应的根本不是同一条指令序列。

**② `bl` 的目标从 `?? ?? 00 94`（通配）变成了 `48 89 FC 97`（硬编码）。** 26.0 的 pattern 里这条 `bl` 用了 `?? ??` 通配，因为每次 Dock 编译后这个函数偏移都不同。26.4 的 pattern 直接把这两个字节写死了（`48 89 FC 97`），说明 asmvik 在 26.4 的 Dock 里确认了这条 `bl` 指令的目标是一个稳定的辅助函数（很可能是某个总在固定位置的 runtime helper），用确定值而不是通配能提高 pattern 匹配的精确性，减少误命中的概率。

**③ `stp x29, x30, [sp, #0x60]` 变成 `[sp, #0x50]`。** 栈帧大小从 `0x70`（112 bytes）缩小到了 `0x60`（96 bytes），和延迟分配一起，是同一次编译器优化的结果。

这三个字节级变化，asmvik 用一个新的 pattern 字符串完整捕获了，调用约定（`x0=ManagedSpace`, `x20=DisplaySpace`）一字不变。

***

### 改动二：`get_dppm_pattern` 的 26.4 分支

这处改动在原来的分析里完全没有提到，但它同样重要。

```c
const char *get_dppm_pattern(NSOperatingSystemVersion os_version) {
    if (os_version.majorVersion == 26) {
        if (os_version.minorVersion >= 4) {
            // macOS 26.4: DPRemoteConnection::_handleEvent: prologue changed
            return "?? ?? 00 ?? 08 ?? ?? 91 00 01 40 F9 E2 03 16 AA E3 03 19 AA ?? ?? ?? 94 ?? ?? ?? ?? 08";
        }
        // 26.0–26.3
        return "?? ?? 00 ?? 08 ?? ?? 91 00 01 40 F9 E2 03 16 AA E3 03 19 AA ?? ?? ?? 94";
    }
    // ...
}
```

`dppm` 是 **`DeskPicturePolicyManager`**（`WallpaperAgentDesktopPictureManager`）的缩写，是 yabai 用于获取 Dock 壁纸管理器实例的 pattern。这个对象在 `do_space_create` 里用于通知 Mission Control 层新 Space 被创建，让壁纸层感知到变化。

对比两个 pattern：

**26.0–26.3：**
```
?? ?? 00 ??   →  adrp  xN, #PAGE          ; 加载某个全局变量的页地址（通配）
08 ?? ?? 91   →  add   x8, xN, #OFFSET    ; 计算实际地址
00 01 40 F9   →  ldr   x0, [x8]           ; 读取 dppm 实例指针
E2 03 16 AA   →  mov   x2, x22            ; 参数准备（x22 → x2）
E3 03 19 AA   →  mov   x3, x25            ; 参数准备（x25 → x3）
?? ?? ?? 94   →  bl    <function>         ; 调用目标函数
              ← pattern 在这里结束
```

**26.4（新增了末尾）：**
```
（前面相同）
?? ?? ?? 94   →  bl    <function>
?? ?? ?? ?? 08   →  额外的后续指令（5字节）  ← 新增
```

26.4 的 pattern 在末尾额外追加了 `?? ?? ?? ?? 08`——这是紧跟在 `bl` 之后的下一条指令的前 5 个字节（`08` 是结尾的确定字节）。为什么要这样做？

**因为 26.4 里 `dppm` 的全局变量地址布局发生了变化，导致前面的 `adrp + add + ldr + mov + mov + bl` 序列在 Dock 里出现了不止一处匹配**。26.0 的 pattern 长度（24字节）在 26.4 里不足以唯一定位 `_handleEvent:` 函数里的那段代码，会误命中别处的相似序列。追加 `?? ?? ?? ?? 08` 这 5 个字节，用下一条指令的结尾特征来消歧义，让 `hexfindseq` 能唯一确定正确位置。

这个改动揭示了 pattern 维护的一个微妙工程问题：**随着 Dock 二进制体积增长和函数数量增加，旧的 pattern 长度可能不再足够唯一**。asmvik 通过延长 pattern（追加更多字节）来重新建立唯一性，而不是改变 pattern 的语义。

***

## 解法 B（我们）：怀疑 ABI 变了，从头用 LLDB 重新推导

我们的路径是：**不假设函数还能被正确调用，先用 LLDB 验证实际崩溃的根本原因，然后根据发现的 ABI 真相决定方案。**

LLDB attach 后，在 pattern 找到的地址打断点，触发时查寄存器：

```
lldb> p $x0
unsigned long = 0x0000000000000001
```

`x0 = 1`，是布尔值而不是对象指针。切到 frame 1 反汇编：

```asm
0x10459eba8 <+84>:  bl   objc_retain     ; 原生代码对 singleton retain
0x10459ebac <+88>:  mov  x20, x0         ; retained 结果 → x20
0x10459ebb0 <+92>:  mov  x0, x23         ; x0 = w23（ldr w23,[x20,#0x38] 读出的 Bool）
0x10459ebb4 <+96>:  bl   0x1045647d8    ; 调用目标，x0=Bool, x20=retained self
```

基于这个发现，我们得出结论：**macOS 26 的 `addSpace` 函数 ABI 变了，`x0` 是 `Bool`，`x20` 是 Swift `self`**，旧的调用约定已经完全无效。

于是我们写了完全不同的调用路径：`asm__call_space_create_tahoe`，`blr` 间接跳转，完整的 clobber 列表，`objc_retain`/`release` 包裹，`display_id_for_uuid()` 多显示器支持。

***

## 谁对谁错？还是各有道理？

**这是整个对比里最值得深挖的部分。**

asmvik 是对的——在 26.0 上原有的调用约定其实没有根本性变化。他的 pattern 在 26.0 上定位到的，是真正的 `addSpace(ManagedSpace*, DisplaySpace*)` 函数（传统 C++ 入口），而不是我们 LLDB 断到的 Swift 包装层。

我们在 LLDB 里打断点时，断到的是**更上层的 Swift 方法**（`SpacesBarWindowController` 的某个方法），这个方法用 `Bool` 作为参数，在内部才调用真正的 C++ `addSpace`：

```
UI 点击 "+"
    └─→ Swift 方法 (x0=Bool, x20=self)         ← 我们 LLDB 断到的位置 (0x1f07d8)
            └─→ C++ addSpace(x0=ManagedSpace*, x20=DisplaySpace*)  ← asmvik pattern 定位的位置
```

两个函数地址不同，`0x1f07d8` 和 pattern 找到的真正 C++ `addSpace` 入口是**不同的函数**。我们的分析定位到了调用链上更高层的 Swift 包装，然后试图直接调用这个包装。这个包装对外部调用不友好——它内部依赖 Swift self 上下文去推断 DisplaySpace，依赖全局状态 `0x488028` 偏移处的 Spaces 单例，还需要 `objc_retain` 配套。这就是为什么我们踩了那么多坑（x0 语义、x20 语义、retain 问题、offset `0x488028`、IOKit 沙箱……）。

**这不是说我们的探索没有价值——恰恰相反**，我们的路径揭示了 macOS 26 内部架构的完整分层，这是 asmvik 的纯 pattern 方法不会告诉你的。而且，我们在 26.4 这条路上踩出来的每一个坑（特别是 IOKit 沙箱、`CGDisplayCreateUUIDFromDisplayID` 的选择），都是在 asmvik 的方法里永远不会遇到的知识。

***

## 架构层面的根本差异

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                        macOS 26 Dock 内部调用链                                │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │  UI 层（Swift）                                                         │  │
│  │  SpacesBarWindowController                                             │  │
│  │    func addSpace(isUserClicked: Bool)                                  │  │
│  │      x0 = Bool (true = user clicked)                                  │  │
│  │      x20 = Swift self（callee-saved，隐式捕获自 caller frame）          │  │
│  │      内部读 self → dock_spaces → DisplaySpace                          │  │
│  │      内部读 0x488028 → Spaces singleton                                │  │
│  │      ← 我们 LLDB 断到的位置 (0x1f07d8)                                │  │
│  └──────────────────────────────┬───────────────────────────────────────── ┘  │
│                                 │ bl → 调用 C++ 核心层                        │
│  ┌──────────────────────────────▼───────────────────────────────────────── ┐  │
│  │  C++ 核心层（DockCore）                                                  │  │
│  │  Spaces::addSpace(ManagedSpace *new_space, DisplaySpace *display_space) │  │
│  │    x0 = ManagedSpace *                                                  │  │
│  │    x20 = DisplaySpace *                                                 │  │
│  │    ← asmvik pattern 定位的位置                                          │  │
│  │    ← ABI 在 macOS 12–26 稳定不变，只有 prologue 字节随编译器版本变化    │  │
│  └──────────────────────────────────────────────────────────────────────── ┘  │
└────────────────────────────────────────────────────────────────────────────────┘

  asmvik 的调用路径：                        我们的调用路径：
  ──────────────────                        ──────────────
  hexfindseq(C++层 pattern)                 hexfindseq(Swift层 pattern → NULL)
       │                                          │
       ▼                                          ▼  addspacefp == 0 触发 ObjC 路径
  asm__call_add_space(                      [ManagedSpace alloc init]
      new_space,      // x0=ManagedSpace*        │
      display_space,  // x20=DisplaySpace*   display_id_for_uuid(display_uuid)
      add_space_fp                               │  (CGDisplayCreateUUIDFromDisplayID)
  )                                             │
       │                                    spaces_array_append(ds, new_space)
       ▼                                         │
  直接调用稳定的 C++ 函数                    objc_msgSend(dppm, addSpace:forDisplayUUID:)
  一行 asm，副作用由函数内部完成                  │
                                            SLSShowSpaces(conn, @[@(spid)])
                                                 │
                                            手动复现所有副作用
```

| 对比维度 | asmvik 解法 | 我们的解法 |
|---|---|---|
| **目标函数层级** | C++ 核心层 `addSpace(ManagedSpace*, DisplaySpace*)` | Swift 包装层 → ObjC runtime 分解 |
| **pattern 策略** | 两处 pattern 更新（`add_space` + `dppm`），精确适配 26.4 | `add_space` pattern 返回 `NULL` 作信号；不涉及 `dppm` pattern |
| **调用宏** | `asm__call_add_space` 完全不变 | 新增 `asm__call_space_create_tahoe`（`blr`，完整 clobber，`memory` barrier）|
| **ABI 假设** | `x0=ManagedSpace*, x20=DisplaySpace*`（macOS 12–26 始终稳定） | `x0=Bool, x20=Swift self`（逆向推导 Swift 包装层约定）|
| **Spaces 单例读取** | 通过已有的 `dock_spaces` 全局指针机制 | 硬编码 offset `0x488028`（LLDB adrp/add decode 得来）|
| **dppm 获取** | `get_dppm_pattern` 匹配后读出指针 | hook `addSpace:forDisplayUUID:` 方法捕获 |
| **多显示器** | `DisplaySpace` 对象直接传入，天然正确 | `display_id_for_uuid()` + `CGDisplayCreateUUIDFromDisplayID` 绕过 IOKit |
| **沙箱感知** | 无需特殊处理（C++ 层不走 IOKit） | 踩了 IOKit 沙箱坑后改用 CoreGraphics SPI |
| **版本耐久性** | pattern 随每次编译可能变（prologue），但 ABI 稳定 | `0x488028` 随每次编译可能变，且还多了 dppm hook 的依赖 |
| **代码量** | +4/-1 行（仅 pattern 字符串）| 新增数百行（宏、辅助函数、retain/release、多显示器逻辑）|
| **揭示的知识** | Dock prologue 编译器优化策略；dppm pattern 歧义消解 | Swift/C++ 调用边界的完整 ABI；Dock 沙箱权限模型；CG SPI 选择 |
| **工程成本** | 极低，每次 Dock 更新用 Ghidra/IDA 找新 pattern 即可 | 高，每次 Dock 重大重构需要重新推导整套 ObjC 路径 |

***

## 最关键的洞察：两条路发现的是两个不同的函数，在两个不同的稳定接缝上工作

我们在 LLDB 里断到 `0x1f07d8` 的时候，认为这就是"addSpace 函数"。asmvik 的 pattern `7F 23 03 D5 FF C3 01 D1 E1 03 1E AA ...` 定位的是另一个地址——入口处有 `sub sp, sp, #0x70`（C++ 标志），参数是对象指针而不是 Bool。

这不仅仅是"我们找到了错误的函数"——更准确的描述是：**我们找到了调用链上层的 Swift 包装，而 asmvik 一直在 C++ 核心层工作**。C++ 层是 macOS 12–26 的稳定接缝：Apple 可以随意重写 Swift 包装层的逻辑（改变 `Bool` 参数的语义、调整捕获方式），但 C++ 核心层的 `addSpace(ManagedSpace*, DisplaySpace*)` 这个函数签名在六代 macOS 里从未改变过，只有 prologue 字节因为 Xcode/clang 版本变化而不同。

asmvik 只需要针对每个新的 Xcode 编译出来的 Dock 版本更新 pattern 字节（在 Ghidra 里搜 `doBindingCommand:display` 函数，找到调用 `addSpace` 的那段，读前几条指令的字节就够了），完全不需要改任何调用逻辑。他的改动只有 8 行，而我们的改动有数百行——差距不是在聪明程度上，而是在**找到了哪一层的稳定接缝**上。

尽管我们在"错误的层次"上做了大量工程补偿，但这趟旅程本身揭示了非常多 asmvik 的方法永远不会告诉你的东西：Dock 的 Swift/C++ 分层架构、Dock 沙箱的精确权限边界、`CGDisplayCreateUUIDFromDisplayID` 作为沙箱可用 SPI 的特殊地位、`asm volatile` 在跨 Swift ABI 调用时的正确写法。这些知识不在任何 Apple 文档里，只有在实际崩溃中一点一点摸出来。
