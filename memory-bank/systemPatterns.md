# System Patterns - yabai

## Core Architecture Patterns

### Event Loop (Event-driven)

```
Carbon Event Tap → Event Handler → Window Manager Update → IPC Response
SkyLight Observer → Callback → State Update → Client Notification
```

### Window Tree (BSP - Binary Space Partition)

```
                    [Root]
                   /      \
              [Left]      [Right]
             /     \      /      \
         [Win1]  [Win2] [Win3]  [Win4]
```

- Insert: split parent, rebalance；Remove: merge siblings；Types: BSP / Stack / Float

### IPC Protocol (Unix Domain Socket)

- Path: `/tmp/yabai_<user>.socket`（daemon）；`/tmp/yabai-sa_<user>.socket`（scripting-addition）
- 格式: `<opcode> [args...]`；响应 JSON/纯文本

## Memory Management

- Arena allocators for window tree nodes；无 RAII，需显式记录 alloc/free 契约

## Scripting Addition Injection

```
payload.m → payload dylib (arm64e) ─┐
loader.m  → loader binary          ─┴→ xxd -i 内嵌到 yabai 二进制
→ 安装到 /Library/ScriptingAdditions/yabai.osax（SIP 部分关闭）
→ Dock 启动时加载 loader，loader dlopen payload 到 Dock 进程内
```

## 领域层指针（细节见 `memory-bank/domains/`，R19）

- **空间创建三代实现 / 空间不变量** → `domains/space-management/principles.md`
- **pattern 编写、单例定位、版本适配流程** → `domains/dock-reverse-engineering/{principles,scenarios,practices}.md`
- **SA 协议、属性位、版本门** → `domains/scripting-addition/{principles,practices,references}.md`
- 本文件只保留**横切**结构（事件循环 / 窗口树 / IPC / 注入流程），其余不在此重复

## Manual UI Path (28 layers, macOS 26)

```
RunLoop Source1 (HIServices) → mshPerform → ... → #05 (0x22abb8) array append
```

（完整调用链与地址见 `docs/reverse-engineering-manual-path-complete-analysis-macos26.md`）
