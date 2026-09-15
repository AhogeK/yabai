# meta — Scripting Addition（SA）

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：环境基线
> **来源**：`src/sa.m` / `src/osax/payload.m` 源码核对

## 边界

yabai 注入 Dock.app 的脚本附加组件与其客户端协议：

- payload（注入体，`src/osax/payload.m` + `arm64_payload.m`/`x64_payload.m`）与 loader
- payload 内嵌进主程序的构建/安装链路（`makefile` → `xxd -i` → `src/sa.m` 落盘 → Dock 加载）
- daemon ↔ SA 的 socket 协议（opcode、握手、属性位、版本门）
- SA 能力与 macOS 版本的适配（**不**负责具体 offset/pattern → `dock-reverse-engineering/`）

## 代码入口

| 位置 | 内容 |
|---|---|
| `src/sa.h` / `src/sa.m` | daemon 侧客户端：安装/卸载、握手校验、各 `scripting_addition_*()` 能力函数 |
| `src/osax/common.h` | `OSAX_VERSION`、`OSAX_ATTRIB_*` 属性位、`sa_opcode` 枚举、socket 路径格式 |
| `src/osax/payload.m` | SA 服务端：`init_instances()`、`handle_message()`、`do_handshake()`、各 `do_*()` |
| `src/osax/loader.m` | Dock 侧加载器（把 payload dlopen 进 Dock 进程） |

## 术语

| 术语 | 含义 |
|---|---|
| **属性位（attrib）** | 握手时 SA 上报的能力掩码；daemon 要求 `OSAX_ATTRIB_ALL` 齐全，缺位 = 触发重装流程 |
| **版本门** | `verify_os_version()`：不覆盖的主版本 → `init_instances()` 直接 return（SA 全静默失效） |
| **代际** | 同一能力在多代 macOS 上的不同实现（daemon 接口不变，payload 内部分流） |
| **SIP 友好模式** | 未关闭 SIP 时的能力降级路径（部分空间/窗口操作走 SkyLight 而非 SA） |

## 环境

| 项目 | 值 |
|---|---|
| 安装位置 | `/Library/ScriptingAdditions/yabai.osax`（loader + payload 包） |
| socket | `/tmp/yabai-sa_<user>.socket` |
| 目标进程 | Dock.app（注入后与 Dock 同地址空间、同权限） |

## 别名与易混概念

| 易混对 | 区分 |
|---|---|
| SA / osax | SA（scripting addition）= 能力本体；osax = 它在 `/Library/ScriptingAdditions/yabai.osax` 的安装形态 |
| payload / loader | loader 被 Dock 加载，负责把 payload dlopen 进 Dock 进程；payload 才是服务端实现 |
| 属性位 / opcode | 属性位 = 握手时上报的**能力掩码**（一次性）；opcode = 单次请求的**动作码** |
| SA socket / daemon socket | `/tmp/yabai-sa_<user>.socket`（daemon→SA）vs `/tmp/yabai_<user>.socket`（用户 CLI→daemon） |
| SIP 关闭 / SIP Friendly | 前者可用 SA 全能力；后者降级为 SkyLight 桥接操作（`SLSPerformAsynchronousBridgedWindowManagementOperation` 等） |
| 代际分流 / 协议变更 | 系统升级只改 payload **内部实现**，opcode/属性位/函数签名是对外契约，不得变 |
| `*_fp` 未解析 / 能力不可用 | 指针为 0 即"本代际不可用"，须显式短路并打日志，不得退化到语义不同的函数 |
