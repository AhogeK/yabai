❯ sudo lldb -p $(pgrep -x Dock)
Password:
(lldb) process attach --pid 64935
Process 64935 stopped
* thread #1, queue = 'com.apple.main-thread', stop reason = signal SIGSTOP
    frame #0: 0x0000000182d13c34 libsystem_kernel.dylib`mach_msg2_trap + 8
libsystem_kernel.dylib`mach_msg2_trap:
->  0x182d13c34 <+8>: ret

libsystem_kernel.dylib`macx_swapon:
    0x182d13c38 <+0>: mov    x16, #-0x30 ; =-48
    0x182d13c3c <+4>: svc    #0x80
    0x182d13c40 <+8>: ret
Target 0: (Dock) stopped.
Executable binary set to "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock".
Architecture set to: arm64e-apple-macosx-.
(lldb) image list -o -f Dock
[  0] 0x00000000049a8000 /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
(lldb) br set -a 0x104B987D8
Breakpoint 1: where = Dock`___lldb_unnamed_symbol_1001f07d8, address = 0x0000000104b987d8
(lldb) c
Process 64935 resuming
Process 64935 stopped
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 1.1
    frame #0: 0x0000000104b987d8 Dock`___lldb_unnamed_symbol_1001f07d8
Dock`___lldb_unnamed_symbol_1001f07d8:
->  0x104b987d8 <+0>:  pacibsp
    0x104b987dc <+4>:  stp    x22, x21, [sp, #-0x30]!
    0x104b987e0 <+8>:  stp    x20, x19, [sp, #0x10]
    0x104b987e4 <+12>: stp    x29, x30, [sp, #0x20]
Target 0: (Dock) stopped.
(lldb) p/x $x0
(unsigned long) 0x0000000000000001
(lldb) p/x $x1
(unsigned long) 0x0b1a800104e1e745
(lldb) p/x $x2
(unsigned long) 0x0000000000000000
(lldb) p/x $x3
(unsigned long) 0x0000000800000003
(lldb) frame select 1
frame #1: 0x0000000104bd2bb8 Dock`___lldb_unnamed_symbol_10022ab54 + 100
Dock`___lldb_unnamed_symbol_10022ab54:
->  0x104bd2bb8 <+100>: bl     0x104b5ee28    ; ___lldb_unnamed_symbol_1001b6e28
    0x104bd2bbc <+104>: bl     0x104ce9f34    ; symbol stub for: objc_release
    0x104bd2bc0 <+108>: ldp    d9, d10, [x19, #0xe8]
    0x104bd2bc4 <+112>: ldp    d11, d12, [x19, #0xf8]
(lldb) p/x $x19
(unsigned long) 0x0000000cbea60a00
(lldb) p/x $x20
(unsigned long) 0x0000000cbe808480
(lldb) p/x $x21
(unsigned long) 0x0000000cbf635260
(lldb) p/x $x22
(unsigned long) 0x0000000cbe0d48c0
(lldb) p/x $w23

error: Couldn't materialize: couldn't read the value of register w23
error: errored out in DoExecute, couldn't PrepareToExecuteJITExpression
(lldb) po $x20
<Spaces: 0xcbe808480>

(lldb) po $x19
SpacesBarWindowController<did:DisplayInfo(uuid: 37D8832A-2D66-02CA-B9F7-8F30A301B230, display: EyeCandyGraphics.CGDisplay(did: 1), bounds: (0.0, 0.0, 2056.0, 1329.0), scaleFactor: 2.0, isMain: true, currentSpace: <ManagedSpace: 0xcbf5d6940> {uuid=14C57FE2-73BF-40AE-9E54-4CEB759B42BE fullscreen=false space=CGSSpace(spid: 3)}, finderIconWindow: Optional(WAWindow(wid: 0x28a6 title: nil))) wid:13207>

(lldb) disassemble --start-address "$pc - 0x50" --count 25
Dock`___lldb_unnamed_symbol_10022ab54:
    0x104bd2b68 <+20>:  stp    x28, x27, [sp, #0x90]
    0x104bd2b6c <+24>:  stp    x26, x25, [sp, #0xa0]
    0x104bd2b70 <+28>:  stp    x24, x23, [sp, #0xb0]
    0x104bd2b74 <+32>:  stp    x22, x21, [sp, #0xc0]
    0x104bd2b78 <+36>:  stp    x20, x19, [sp, #0xd0]
    0x104bd2b7c <+40>:  stp    x29, x30, [sp, #0xe0]
    0x104bd2b80 <+44>:  add    x29, sp, #0xe0
    0x104bd2b84 <+48>:  stp    x1, x0, [sp, #0x18]
    0x104bd2b88 <+52>:  adrp   x25, 606
    0x104bd2b8c <+56>:  add    x25, x25, #0x28
    0x104bd2b90 <+60>:  ldr    x0, [x25]
    0x104bd2b94 <+64>:  cbz    x0, 0x104bd2f94 ; <+1088>
    0x104bd2b98 <+68>:  mov    x19, x20
    0x104bd2b9c <+72>:  mov    x24, x2
    0x104bd2ba0 <+76>:  mov.16b v8, v0
    0x104bd2ba4 <+80>:  ldr    w23, [x20, #0x38]
    0x104bd2ba8 <+84>:  bl     0x104ce9f44    ; symbol stub for: objc_retain
    0x104bd2bac <+88>:  mov    x20, x0
    0x104bd2bb0 <+92>:  mov    x0, x23
    0x104bd2bb4 <+96>:  bl     0x104b987d8    ; ___lldb_unnamed_symbol_1001f07d8
->  0x104bd2bb8 <+100>: bl     0x104b5ee28    ; ___lldb_unnamed_symbol_1001b6e28
    0x104bd2bbc <+104>: bl     0x104ce9f34    ; symbol stub for: objc_release
    0x104bd2bc0 <+108>: ldp    d9, d10, [x19, #0xe8]
    0x104bd2bc4 <+112>: ldp    d11, d12, [x19, #0xf8]
    0x104bd2bc8 <+116>: mov    x0, #0x0 ; =0
(lldb) br delete
About to delete all breakpoints, do you want to do that?: [Y/n] Y
All breakpoints removed. (1 breakpoint)
(lldb) detach
Process 64935 detached
(lldb) quit

🛑 疑问 1 终结：PAC 签名问题是不存在的！
你抓到的这段汇编，堪称最完美的“不在场证明”：
Code snippet
0x104bd2bb0 <+92>: mov x0, x23
0x104bd2bb4 <+96>: bl 0x104b987d8 ; ___lldb_unnamed_symbol_1001f07d8

关键点在于 bl 指令。
在 ARM64 中，bl（Branch with Link）是相对地址直接跳转，它根本不经过 PAC 签名验证！
只有当使用 blrab、blr、braa 这种寄存器间接跳转时，才会触发指针验证。因为 0x1f07d8 这个函数是编译时就静态链接在 Dock 二进制文件里的，苹果的代码是直接跳过去的。
💡 结论：
如果 yabai 在尝试调用或 Hook 这个函数时崩溃了，绝对不是因为 PAC 签名报错。极大可能是由于 yabai 传入的参数不对，或者在重定向函数指针时破坏了堆栈。
🔍 疑问 2 终结：真实的参数到底是什么？
我们来看看 Frame 0（案发第一现场）你抓到的真实参数：
$x0 = 0x0000000000000001
$x1 = 0x0b1a800104e1e745 (典型的 Swift/ObjC Tagged Pointer 或 ISA 指针)
$x2 = 0x0000000000000000
$x3 = 0x0000000800000003
再结合 Frame 1 的调用前准备：
Code snippet
0x104bd2b90 <+60>: ldr x0, [x25] // x0 = 全局 Spaces 对象
0x104bd2b94 <+64>: cbz x0, 0x104bd2f94 // 如果是 NULL 就跳走
...
0x104bd2ba4 <+80>: ldr w23, [x20, #0x38] // w23 = 从旧的 x20 对象里读出 1
0x104bd2ba8 <+84>: bl 0x104ce9f44 // 调用 objc_retain(Spaces)
0x104bd2bac <+88>: mov x20, x0 // x20 现在变成了安全的 Spaces 对象
0x104bd2bb0 <+92>: mov x0, x23 // x0 = 1
0x104bd2bb4 <+96>: bl 0x104b987d8 // 调用函数！

真相大白：
这个 0x1f07d8 并不是一个普通的 Objective-C 方法 [Spaces addSpace:]。
它是一个底层的 C/C++ 辅助函数，或者是一个去糖化 (Desugared) 的 Swift 方法。
它在调用时，并没有把 Spaces 实例对象放在第一个参数 $x0（像标准 ObjC 那样），而是把 1 放在了 $x0。
那 Spaces 对象去哪了？答案很可能藏在调用约定的特殊寄存器里（比如 Swift self 经常放在 $x20），或者它就是一个内部的 Block，捕获了周围的环境。

这次 LLDB 输出把真相完全暴露了。让我精准分析：

## 🔬 汇编完整还原

```
<+60>:  ldr    x0, [x25]          // x0 = Spaces 单例 (0xcbe808480)
<+64>:  cbz    x0, <+1088>        // nil guard
<+68>:  mov    x19, x20           // x19 = SpacesBarWindowController（保存）
<+76>:  mov.16b v8, v0            // 保存某个向量寄存器
<+80>:  ldr    w23, [x20, #0x38]  // w23 = *(SpacesBarWindowController + 0x38) = 1
<+84>:  bl     objc_retain        // retain(Spaces 单例)，返回值仍在 x0
<+88>:  mov    x20, x0            // x20 = Spaces 单例（x20 被覆盖！）
<+92>:  mov    x0, x23            // x0 = 1（w23 的值）
<+96>:  bl     0x1f07d8           // 调用！
```

**Swift 调用约定揭示**：`0x1f07d8` 是一个 **Swift 方法**，`self` 放在 `x20`！

调用时的寄存器状态：

* `x0 = 1`（整数参数）
* `x20 = Spaces 单例`（Swift self）

***

## 💥 崩溃根因

你现在的 asm 宏只设置了 `x0 = display_id`，**完全没有设置 `x20 = Spaces 单例`**。函数进去拿 `x20` 当 `self` 用，读到的是垃圾值，立刻崩溃。

***

## ✅ 修复方案

## `arm64_payload.m`

```
// ====== 【修改：替换 Tahoe space_create 宏，补上 x20 = Swift self (Spaces singleton)】 ======
// Swift method calling convention: self in x20, first arg in x0
// Confirmed by LLDB Frame1 disassembly:
//   <+88>: mov x20, x0   (x0 = retained Spaces singleton)
//   <+92>: mov x0, x23   (x23 = display_id = 1)
//   <+96>: bl  0x1f07d8
#define asm__call_space_create_tahoe(display_id, spaces_self, func)  \
    asm volatile(                                                     \
        "mov x0, %w0\n"                                              \
        "mov x20, %1\n"                                              \
        :                                                            \
        : "r"((int32_t)(display_id)), "r"((uintptr_t)(spaces_self)) \
        : "x0", "x20"                                               \
    );                                                               \
    ((void (*)(void))(func))()
```

## `payload-2.m` 中的调用点

```
// ====== 【修改：传入 Spaces 单例作为 Swift self（x20）】 ======

// Read the Spaces singleton from global variable (file offset 0x488028, confirmed via LLDB)
// At call time: x20 = Spaces singleton, x0 = display_id (int32_t = 1 for main display)
uintptr_t dock_text_base = base_addr + image_slide_val;
uintptr_t spaces_global_ptr = dock_text_base + 0x488028ULL;
id spaces_singleton = *(id *)spaces_global_ptr;

if (!spaces_singleton) {
    NSLog(@"[yabai-sa][SPACE] ERROR: Spaces singleton is nil at 0x%llx", spaces_global_ptr);
    CFRelease(block_display_uuid);
    return;
}

NSLog(@"[yabai-sa][SPACE] spaces_singleton=%p, display_id=%u", (void *)spaces_singleton, display_id);

dispatch_sync(dispatch_get_main_queue(), ^{
    asm__call_space_create_tahoe(display_id, spaces_singleton, space_create_addr);
});
```

***

## 🧮 `spaces_global_ptr` 地址验证

从这次 LLDB 可以交叉验证：

* Slide = `0x049a8000`
* `x25` 读出地址 = `0x104bd2b88 <+52>: adrp x25, 606` → `0x104b987d8` 附近的 page 计算
* 上次 LLDB 确认：` $x25 = 0x1047fc028`，`x/1xg $x25 = 0xcbe808480`
* `po $x20 = <Spaces: 0xcbe808480>` ✅ 完全一致

所以 `spaces_global_ptr` 的文件偏移 = `0x1047fc028 - 0x100000000 - 0x04374000 = 0x488028` 仍然有效。

但注意 `base_addr + image_slide_val` 在你的 `payload-2.m` 里就是 `staticBaseAddress() + imageSlide()`，最终结果是 `0x100000000 + slide`，所以：

```
// 正确写法：文件偏移直接加到 slide 上
uintptr_t spaces_global_ptr = (uintptr_t)image_slide_val + 0x100000000ULL + 0x488028ULL;
//                                        ↑ 即 0x049a8000                  ↑ 文件偏移
// = 0x1049e8028  → 取值得到 Spaces 单例指针
```

验证一下：`0x100000000 + 0x049a8000 + 0x488028 = 0x104e30028`……等等，这次的 slide 是 `0x049a8000`，上次是 `0x04374000`，每次重启都不同。计算逻辑里用动态的 `image_slide_val` 就行，不要硬编码。

编译测试后把日志发我，现在应该能看到 `space_create_entry returned` 了。
