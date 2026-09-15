# principles — SA 的不变量

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：已验证
> **来源**：`sa.m` 握手/校验源码核对 + 27.0 实测（属性位与版本门生效）

## 1. 能力上报必须与真实能力一致

`do_handshake()` 的属性位是 daemon 判断"SA 是否可用"的唯一依据：

- 缺位 → `scripting_addition_perform_validation()` 判为"payload 不支持本 macOS 版本" → 触发重装/重启 Dock 的循环
- 因此能力**存在即上报**：同一能力有多代实现时，属性条件必须是"任一代可用"
  例：`OSAX_ATTRIB_ADD_SPACE` ← `add_space_fp || space_create_entry_fp || wm_create_space_fp`

## 2. payload 有改动 → 必须 bump `OSAX_VERSION`

`OSAX_VERSION` 是 daemon 与 SA 的唯一版本契约；不变则不会触发重装，用户会一直跑旧 payload。版本差异会触发"重装 payload + 重启 Dock"。

## 3. 能力实现按代际分流，daemon 接口不变

`src/sa.h` 的能力函数签名与 opcode 是稳定契约（`yabairc` 脚本依赖）。系统升级只改 payload 内部实现（新分支/新符号），不改对外协议。

## 4. 一切注入/重启动作由用户执行

`yabai --load-sa` / `--restart-service` / 重装 SA / 重启 Dock 涉及 Accessibility 授权与注入确认，AI 只输出命令（R3）。

## 5. payload 内不做能力猜测

payload 拿不到的能力（如未解析的函数指针）必须**显式置 0 并跳过**，不得回退到"语义不同的函数"（例：27 的 `add_space` 若误用 pattern 会命中"把空间移动到显示索引"的函数）。

## 6. Dock 沙箱的行为约束

IOKit 在 Dock 沙箱内**静默失败**（返回 `MACH_PORT_NULL`）而非报错，逻辑"正确"却永远走 fallback：显示器 UUID 一律用 CoreGraphics（`CGDisplayCreateUUIDFromDisplayID`）。

## 7. 线程与调用位置

Dock 内部 Swift 方法（26.x 的空间入口）要求主线程 → `dispatch_sync(dispatch_get_main_queue(), …)`；框架级同步 XPC API（27 的 WindowManager）与主线程无关 → 在 SA 自己的连接线程直接调用，避免主线程死锁。
