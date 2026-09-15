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

## Space Creation 三代实现（版本演进）

| 世代 | 实现 | 调用方式 |
|------|------|---------|
| ≤ 25 | Dock `addSpace` 函数 | `x0=new_space, x20=display_space`（asm 宏） |
| 26 | Dock Swift `space_create_entry` | `x0=display_id, x20=Spaces self`（原子 asm + `blr`） |
| 27 | **WindowManager.framework** `synchronouslyRequestCreateManagedSpace(displayUUID:)` | dlsym + Swift ABI（x20=self，x0/x1=String，错误 x21） |

## macOS 26/27 动态定位模式

- **Spaces 单例**: pattern（`doBindingCommand:display` 反汇编特征）→ `decode_adrp_add`；26 另有 DOUBLE-ANCHOR 兜底（搜索 `bl space_create_entry` 后回溯 adrp/add）
- **DPPM 单例**: 26 为 setter 控制流指纹（cbnz+str）；27 指纹失效 → 退回 `DPRemoteConnection::_handleEvent:` pattern（`adrp+add+ldr` 融合）
- **全局语义画像**: `dyld_info -fixups` 建 selector→字符串映射 → 扫描 `__objc_stubs` 得 stub→selector → 对 `__text` 做寄存器级抽象解释，统计"全局 × 方法名"定位单例归属

### Manual UI Path (28 layers, macOS 26)

```
RunLoop Source1 (HIServices) → mshPerform → ... → #05 (0x22abb8) array append
```
