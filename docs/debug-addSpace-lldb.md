# lldb 调试指南：追踪 addSpace:forDisplayUUID: 的 receiver

## 准备工作

```bash
# 1. 关闭 SIP 的部分保护（如果需要）
# 重启进入 Recovery Mode，执行：
# csrutil enable --without debug

# 2. 确保 Dock 已启动
killall Dock  # 让系统自动重启 Dock
sleep 2
```

## 步骤 1：附加到 Dock 进程

```bash
sudo lldb -p $(pgrep -x Dock)
```

## 步骤 2：设置断点

```lldb
# 方法 A：直接断实例方法
(lldb) breakpoint set -n "-[DockCore.WallpaperAgentDesktopPictureManager addSpace:forDisplayUUID:]"
(lldb) breakpoint set -n "-[DockCore.WallpaperAgentDesktopPictureManager init]"

# 方法 B：如果方法名不对，用 selector 地址断点
# 先找到 selector 字符串地址
(lldb) memory find -c "addSpace:forDisplayUUID:" /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
# 然后找到引用这个 selector 的代码位置

# 启用断点
(lldb) breakpoint enable
```

## 步骤 3：触发断点

```bash
# 在另一个终端执行
yabai -m space --create

# 或者手动：
# 1. 打开 Mission Control
# 2. 点击 + 按钮创建桌面
```

## 步骤 4：查看寄存器

```lldb
# 断点后首先查看寄存器
(lldb) register read x0 x1 x2 x3 x4 x5

# x0 = receiver (self)
# x1 = selector (_cmd)
# x2 = 第一个参数 (space)
# x3 = 第二个参数 (displayUUID)

# 打印对象
(lldb) po $x0
(lldb) po $x2
(lldb) po $x3

# 查看 receiver 的类
(lldb) po [$x0 class]
(lldb) po object_getClass($x0)
```

## 步骤 5：查看调用栈

```lldb
# 完整回溯
(lldb) bt

# 带帧信息的回溯
(lldb) bt all

# 查看上一个帧（调用者）
(lldb) frame select 1
(lldb) disassemble --frame
(lldb) register read

# 返回帧 0
(lldb) frame select 0
```

## 步骤 6：分析调用者的数据流

```lldb
# 在调用者的汇编中找 x0 的来源
(lldb) disassemble --frame
# 查找类似这样的指令：
# ldr x0, [xN, #offset]  ← 从 ivar 加载
# bl _objc_msgSend       ← 从 getter 返回
# mov x0, xN             ← 从寄存器传递
```

## 步骤 7：持续追踪

```lldb
# 继续执行到下一次调用
(lldb) continue

# 或者单步执行
(lldb) step-instruction
(lldb) step-over
(lldb) step-out
```

## 预期输出示例

```
(lldb) breakpoint set -n "-[DockCore.WallpaperAgentDesktopPictureManager addSpace:forDisplayUUID:]"
Breakpoint 1: where = Dock`-[DockCore.WallpaperAgentDesktopPictureManager addSpace:forDisplayUUID:], address = 0x0000000100xxxxx

(lldb) continue
Process 12345 resuming

# 断点后
Stop reason: Breakpoint 1 hit

(lldb) register read x0 x1 x2 x3
     x0 = 0x0000000123456789  ← receiver 地址
     x1 = 0x0000000100abcdef  ← selector 地址
     x2 = 0x0000000100fedcba  ← space 参数
     x3 = 0x0000000100123456  ← displayUUID 参数

(lldb) po $x0
<DockCore.WallpaperAgentDesktopPictureManager: 0x123456789>

(lldb) po [$x0 class]
DockCore.WallpaperAgentDesktopPictureManager

(lldb) bt
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint
  * frame #0: 0x0000000100xxxxx Dock`-[DockCore.WallpaperAgentDesktopPictureManager addSpace:forDisplayUUID:]
    frame #1: 0x0000000100yyyyy Dock`-[SomeController createSpace:] + 123
    frame #2: 0x0000000100zzzzz Dock`-[MissionController handlePlusButton:] + 456
    ...
```

## 关键信息记录

每次断点后记录：

| 项目 | 值 | 说明 |
|------|-----|------|
| `x0` (receiver) | `0x...` | 实例地址 |
| `receiver class` | `...` | 类名 |
| `x2` (space) | `0x...` | space 参数 |
| `x3` (displayUUID) | `0x...` | displayUUID 参数 |
| 调用者 (frame 1) | `...` | 谁调用的 |
| 调用者 x0 来源 | `...` | 从哪来的 |

## 常见问题

### Q: 断点无法命中？

**A**: 可能原因：
1. 方法名不对（Swift 方法需要不同的断点语法）
2. 代码路径不经过这个方法
3. SIP 阻止了调试

尝试：
```lldb
# 列出所有包含 addSpace 的方法
(lldb) breakpoint set -r "addSpace"

# 或者用地址断点
(lldb) breakpoint set --address 0x100xxxxx
```

### Q: po 命令失败？

**A**: 可能对象指针无效。尝试：
```lldb
(lldb) memory read --size 8 --count 4 $x0
(lldb) p (id)$x0
```

### Q: 无法附加到 Dock？

**A**: 需要关闭 SIP 的 debug 保护：
1. 重启进入 Recovery Mode
2. 打开终端执行：`csrutil enable --without debug`
3. 重启

## 替代方案：在 yabai 中添加日志

如果 lldb 调试困难，可以在 yabai 代码中添加：

```c
// 在 do_space_create 中
// 通过 objc_msgSend 调用 addSpace:forDisplayUUID: 前
debug_log(@"Calling addSpace: receiver=%p class=%s",
          (void *)dp_desktop_picture_manager,
          dp_desktop_picture_manager ? class_getName(object_getClass(dp_desktop_picture_manager)) : "nil");
```

然后查看 `/tmp/yabai-sa-debug.log`。
