# scenarios — 触发场景 → 判断 → 动作

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：方法论
> **来源**：S1/S4 依据 `sa.m` 安装链路源码；S1 已在 27.0 走通

## S1. daemon 报 "payload (0x…) doesn't support this macOS version!"

**判断**：这是**属性位缺失**，不是版本号问题。

**动作**：
1. `log show --last 5m --predicate 'process == "Dock"' | grep yabai-sa` 看初始化日志（`dock.spaces found` / `dppm found` / `[WM] … resolved`）；
2. 定位缺失的能力位对应哪个 `*_fp` 未解析；
3. 若是版本门未覆盖 → 走 `dock-reverse-engineering/scenarios.md` S1；
4. 若是能力代际变化 → 修 `do_handshake()` 的上报条件（原则 1）。

## S2. 新增一个 SA 能力

1. `src/osax/common.h`：加 `SA_OPCODE_*` + 对应 `OSAX_ATTRIB_*` 位（并纳入 `OSAX_ATTRIB_ALL`）；
2. `src/osax/payload.m`：加 `do_xxx()` + `handle_message()` 分支；
3. `src/sa.h` / `src/sa.m`：加 daemon 侧 `scripting_addition_xxx()`（`sa_payload_init()` + `pack()` + `sa_payload_send(opcode)`）；
4. daemon 业务侧接入；
5. bump `OSAX_VERSION`（原则 2）；
6. 编译双架构 → 交用户安装验证（原则 4）。

## S3. daemon 明明调用了 SA 但完全没反应

**判断顺序**：SA 是否加载（Dock 日志有无 `[yabai-sa] loaded payload..`）→ 握手是否通过 → 目标 `do_xxx()` 是否因指针为 0 提前 return（payload 内多处 `if (!fp) return;`）。

**动作**：先看日志再改代码；不要先怀疑 daemon 逻辑。

## S4. SA 安装 / 重装失败或未生效

**判断**：安装链路 = 落盘 `/Library/ScriptingAdditions/yabai.osax` → 重启 Dock 让 loader 生效；任一步失败都会表现为"握手连不上"。

**动作**：
1. 确认 SIP 状态满足 `scripting_addition_is_sip_friendly()`（需要 `CSR_ALLOW_UNRESTRICTED_FS`）与 arm64e 可用；
2. 确认安装目录内容齐全（loader + payload 包 + 两个 plist，版本号为当前 `OSAX_VERSION`）；
3. 未生效时**告知用户手动重启 Dock / yabai**（原则 4），AI 不代为重启；
4. 重装后仍连不上 → 看 Dock 日志是否加载了旧路径的 payload（残留目录）。

## S5. 排查 SA 崩溃/卡死

- 卡死优先查线程模型（原则 7）：主线程 `dispatch_sync` + 同步 XPC 互相等待；
- 崩溃优先查调用约定（Swift `x20` self / `x0–x1` 参数 / `x21` 错误寄存器）是否与实测一致。
