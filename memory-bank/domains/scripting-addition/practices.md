# practices — SA 具体做法与踩坑

> **系统基线**：macOS 27.2 (26B123) · Dock 2571.1.32.402 · WindowManager 462.1.41.404
> **最后验证**：2026-10-28 · **状态**：已验证
> **来源**：命令与 asm 宏约束本机跑通；27.2 崩溃/恢复/握手实测 + `payload.m` 源码核对

## 1. 日志排查（第一手证据）

```bash
log show --last 5m --predicate 'process == "Dock"' | grep -E "yabai-sa|yabai-sa\]\[WM\]"
```

payload 内日志前缀约定：`[yabai-sa]`（通用）、`[yabai-sa][SPACE]`、`[yabai-sa][DPPM]`、`[yabai-sa][WM]`（WindowManager 路径）。**新增路径必须打日志**，否则现场无法定位。

## 2. 版本门写法（`verify_os_version`）

```c
#elif __arm64__
    ... else if (os_version.majorVersion == 27) {
        macOSSequoia = true;      // 26+ 一律置位（SIP/Dock 行为分界）
        return true;
    }
```

- x86_64 分支**只在确有 Intel 版本**时添加（27 无 Intel）
- 缺分支 = `init_instances()` 直接 return，所有能力为 0

## 3. 握手协议（字节布局）

请求：`0x01 0x00 SA_OPCODE_HANDSHAKE`（3 字节）
响应：`<OSAX_VERSION 字符串> \0 <uint32 attrib 小端> \n`

daemon 侧用 `(attrib & OSAX_ATTRIB_ALL) == OSAX_ATTRIB_ALL` 判定完整性。

## 4. 能力调用的 register 约定速查

| 场景 | 约定 |
|---|---|
| Dock 内 ObjC 方法 | 常规 `objc_msgSend`（self 在 x0） |
| Dock 内 Swift 实例方法（26） | `x0` = 参数、`x20` = self（callee-saved） |
| 框架 Swift 实例方法（27） | `x20` = self、`x0/x1` = 2-word 值（String）、`x21` = `swift_error*`、返回 `x0` |
| 框架 Swift 静态 getter | 先 `Ma` 取 metatype → `x20` = metatype → getter，实例返回 `x0` |
| `throwing` 调用 | 调用前 `x21 = 0`；返回后 `x21 != 0` 即失败，需 `swift_errorRelease` |

### 4.1 arm64e 间接调用规则（**血泪教训**）

- `dlsym()` 在 arm64e 下返回**已带 PAC 签名的函数指针**（日志里表现为高位非零，如 `0xfe2c0002b84abec4`）
- 调用这类指针**必须用认证分支**：`mov x16, fn; blraaz x16`（= `blraa` + modifier 0，key A），或直接走 C 函数指针对话（编译器自行生成 `blraaz`）
- **用裸 `blr` 会立刻以 `PAC_EXCEPTION` 杀死进程**；Dock 崩溃时 NSLog 缓冲会丢，现场只剩 `~/Library/Logs/DiagnosticReports/Dock-*.ips`（见 `dock-reverse-engineering/scenarios.md` S6）
- 自己算出来的裸地址（pattern 命中的 `baseaddr + offset`）则相反：**先签名再调用**
  （`ptrauth_sign_unauthenticated(ptr, ptrauth_key_asia, 0)` + 认证调用）；若坚持裸 `blr`，该指针必须保持未签名
- 判定口诀：**指针是"来自 dlsym / 编译器取址" → 已签名 → 认证调用；是"自己算出来的" → 未签名 → 先签名或裸调用，两者不可混**

详见 `dock-reverse-engineering/practices.md` §6（asm 宏约束）。

## 5. 指针未解析时的安全写法

```c
if (capability_fp != NULL) { ...; return; }   // 显式短路
```

禁止"退化到语义不同的函数"（原则 5）。新增代际路径时，旧路径的 `*_fp` 应显式置 0（如 27 的 `get_add_space_offset()` 返回 0），避免误命中。

## 5.1 Swift 错误的可读化（排查必备）

`x21` 里的 `swift_error*` 必须转成可读文本再记日志，否则只有裸指针：

```c
void *bridge = dlsym(RTLD_DEFAULT, "_swift_stdlib_bridgeErrorToNSError");   // 注意前导下划线
@autoreleasepool {                                   // 桥接结果是 autoreleased
    id ns = ((id (*)(uint64_t)) bridge)((uint64_t) swift_error);
    NSLog(@"... failed: %@", ns);                    // 得到 domain / code / description
}
((void (*)(uint64_t)) swift_errorRelease_fp)(swift_error);
```

- `swift_errorRelease` / `swift_errorRetain` / `_swift_stdlib_bridgeErrorToNSError` / `swift_getErrorValue` / `swift_getTypeName` 均可 `dlsym` 到（`swift_bridgeErrorToNSError` 这个名字**不存在**）
- 抛错时 `x0` 是**未定义值**：必须在判断 `x21 == 0` 之后再使用返回值，否则会把垃圾当 spid 上报

## 6. 构建与验证

```bash
mkdir -p /tmp/<topic>/build/yabai_bin
DEVELOPER_DIR=/Library/Developer/CommandLineTools make BUILD_PATH=/tmp/<topic>/build
```

- 只编译 payload 快速验证：`xcrun clang src/osax/payload.m -shared -fPIC -O3 -arch arm64e -o /tmp/p.m -F/System/Library/PrivateFrameworks -framework SkyLight -framework Foundation -framework Carbon`
- **验证权在用户**：安装/重启后由用户回传 `log show` 结果（原则 4）。

## macOS 27 空间创建：payload 侧三个必须守住的点（2026-09-15 实测）

1. **签名状态决定分支指令**（本域最易错）：`ptrauth_sign_unauthenticated` 过的指针（addSpace/removeSpace/moveSpace/setFrontWindow）→ C 调用（`braaz`）；pattern 扫出的**未签名**裸地址（27 的 create helper / cid getter，26 的 space_create_entry）→ 裸 `blr`；dlsym 指针 → `blraaz`。**三者不可互替**，27 上双向都踩过崩溃。
2. **Swift 私有单例不能 dlsym**：`__swiftEmptyArrayStorage` 在 Dock 内 `dlsym(RTLD_DEFAULT, …)` 返回 NULL；传 NULL 会让 Dock 崩在 helper 内（`[NULL+0x10]`）。正解是从调用点 `adrp+ldr` 解码 literal pool，且**解析失败时跳过调用**而不是传 NULL。
3. **主线程**：Dock 的创建调用点都在主线程，payload 也要 `dispatch_sync(dispatch_get_main_queue(), …)`；注意 block 内 asm 输出操作数需经局部变量再写回（block 捕获是 const）。

### 空间身份：Swift String 参数就是新空间的 uuid（2026-10-23 更正）

create helper 的第 4 个参数（Swift String）原样进入 `CGSSpaceCreate` 的 `@{type, uuid, pid}`，**它就是新空间的身份**。绝不能传显示器 UUID：同显示器上所有由 yabai 创建的空间会共享一个身份，WindowManager 按身份持久化并在开机恢复，重复身份全部塌缩到同一 id（`managed space order: [6,6,…]`）→ Mission Control 只剩 1 个桌面、无壁纸。系统 “+” 每次生成新 UUID（实测 id 33 = `442D311F…`）；payload 用 `CFUUIDCreate` + `CFUUIDCreateString` 生成后传入，显示器 UUID 只用于落点校验。

### 扫描边界与构建闸门（2026-10-28 事故）

- `hex_find_seq` 的固定窗口（0x1286a0）必须再钳制到宿主 `__TEXT` 末尾（`getsegbyname("__TEXT")` 的 `vmaddr + vmsize + slide`）。OS 更新后特征码失配时，扫描会读进段末尾保护页，Dock 直接 SIGBUS（本次：`0x2b0000 + 0x1286a0 > 0x3b9b80`）。
- macOS 27.x 必须做 Dock 构建闸门（`CFBundleVersion` 白名单）；未知构建拒绝初始化并打日志——**宁可不注入，也不能崩 Dock**。

### pattern 命中 ≠ 函数身份（2026-10-28 27.2 教训）

Dock 重编译后，`remove_space` 的旧特征码在 27.2 仍命中 0x12dbcc，但反汇编显示该函数只保存 4 个参数、逻辑与 removeSpace 不符——这是**伪命中**。启用任何 pattern 命中前，必须核对 prologue 的参数保存、关键调用（如 `CGSSpaceCreate`）与选择器；否则会在调用时把错误地址当函数指针用，直接崩 Dock。

### macOS 27.2 的 move/排序走 SLS（2026-10-28）

Dock 重编译后 `moveSpace` / DPPM 入口消失；SLS 仍有底层布局 API：跨显示器 `CGSMoveManagedSpaceToDisplayIndex(cid, sid, displayUUID CFString, flags)`；同显示器排序用事务 `SLSTransactionCreate(cid)` → `SLSTransactionMoveManagedSpaceToDisplayAfterSpace(tx, sid, displayUUID, afterSid)` → `SLSTransactionCommit(tx, 1)` → `CFRelease(tx)`。参数形态由 Dock/WM 调用点反汇编确认（x2 为桥接后的 NSString）。

### 握手属性位要与实际能力一致（2026-10-28 审计）

payload 只按函数指针是否解析来上报能力位（ADD/REM/MOV/SET_WINDOW/ANIM_TIME/DPPM）。macOS 27.2 上 destroy/move 改由 SLS 实现、对应 Dock 指针为 0，若照旧上报就会让 daemon 判定“payload 不支持该系统版本”。规则：**能力位按实现上报**（27.2 用 SLS 实现也要置 REM/MOV）；daemon 侧只校验真正必需的子集 `OSAX_ATTRIB_REQUIRED` = **ADD_SPACE | REM_SPACE | MOV_SPACE**，可选位（DOCK_SPACES/DPPM/SET_WINDOW/ANIM_TIME）缺失不应判负。

### 固定地址必须做段范围校验（2026-10-28 审查）

构建锁定的 27.2 profile 使用固定地址（`__DATA` 单例槽、`__TEXT` helper、literal pool 槽）。除 Dock 构建串白名单外，读取前必须用 `getsegbyname` 校验目标落在允许段内（`__DATA` / `__DATA_CONST` / `__AUTH_CONST` / `__TEXT`）；`image_slide()` 失败或 text 尾未知时扫描/读取一律 fail-closed。版本串相同但二进制变体的场景下，这是最后一道防线。
