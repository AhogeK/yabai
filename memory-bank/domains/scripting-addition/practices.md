# practices — SA 具体做法与踩坑

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：已验证
> **来源**：命令与 asm 宏约束本机跑通；日志前缀与 `payload.m` 源码核对

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

详见 `dock-reverse-engineering/practices.md` §6（asm 宏约束）。

## 5. 指针未解析时的安全写法

```c
if (capability_fp != NULL) { ...; return; }   // 显式短路
```

禁止"退化到语义不同的函数"（原则 5）。新增代际路径时，旧路径的 `*_fp` 应显式置 0（如 27 的 `get_add_space_offset()` 返回 0），避免误命中。

## 6. 构建与验证

```bash
mkdir -p /tmp/<topic>/build/yabai_bin
DEVELOPER_DIR=/Library/Developer/CommandLineTools make BUILD_PATH=/tmp/<topic>/build
```

- 只编译 payload 快速验证：`xcrun clang src/osax/payload.m -shared -fPIC -O3 -arch arm64e -o /tmp/p.m -F/System/Library/PrivateFrameworks -framework SkyLight -framework Foundation -framework Carbon`
- **验证权在用户**：安装/重启后由用户回传 `log show` 结果（原则 4）。
