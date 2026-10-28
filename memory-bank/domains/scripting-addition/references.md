# references — SA 协议与路径事实表

> **系统基线**：macOS 27.2 (26B123) · Dock 2571.1.32.402 · WindowManager 462.1.41.404
> **最后验证**：2026-10-28 · **状态**：已验证
> **来源**：与 `src/osax/common.h` 逐项核对（属性位/opcode/版本号）+ 27.2 真机日志

## 属性位（`src/osax/common.h`）

| 位 | 名称 | 含义 |
|---|---|---|
| 0x01 | `OSAX_ATTRIB_DOCK_SPACES` | `dock_spaces` 单例可用 |
| 0x02 | `OSAX_ATTRIB_DPPM` | DPPM 单例可用 |
| 0x04 | `OSAX_ATTRIB_ADD_SPACE` | 创建空间可用（任一代际） |
| 0x08 | `OSAX_ATTRIB_REM_SPACE` | 销毁空间可用 |
| 0x10 | `OSAX_ATTRIB_MOV_SPACE` | 移动空间可用 |
| 0x20 | `OSAX_ATTRIB_SET_WINDOW` | `setFrontWindow` 可用 |
| 0x40 | `OSAX_ATTRIB_ANIM_TIME` | 动画时间补丁点可用 |

## opcode（`enum sa_opcode`）

| 值 | 名称 | 值 | 名称 |
|---|---|---|---|
| 0x01 | `HANDSHAKE` | 0x0B | `WINDOW_SHADOW` |
| 0x02 | `SPACE_FOCUS` | 0x0C | `WINDOW_FOCUS`（daemon 侧当前为 `#if 1` 关闭） |
| 0x03 | `SPACE_CREATE` | 0x0D | `WINDOW_SCALE` |
| 0x04 | `SPACE_DESTROY` | 0x0E/0x0F | `WINDOW_SWAP_PROXY_IN/OUT` |
| 0x05 | `SPACE_MOVE` | 0x10/0x11 | `WINDOW_ORDER` / `ORDER_IN` |
| 0x06 | `WINDOW_MOVE` | 0x12 | `WINDOW_LIST_TO_SPACE` |
| 0x07/0x08 | `WINDOW_OPACITY` / `_FADE` | 0x13 | `WINDOW_TO_SPACE` |
| 0x09 | `WINDOW_LAYER` | 0x0A | `WINDOW_STICKY` |

## 关键常量与路径

| 项目 | 值 |
|---|---|
| `OSAX_VERSION` | 2.1.41（macOS 27.2 支持，7.2.13） |
| socket 路径 | `/tmp/yabai-sa_%s.socket`（`SA_SOCKET_PATH_FMT`） |
| socket 缓冲 | `SA_SOCKET_BUFF_LEN` = 0x1000 |
| 安装目录 | `/Library/ScriptingAdditions/yabai.osax` |
| payload/loader 产物 | `$(BUILD_PATH)/yabai_bin/{payload_bin.c,loader_bin.c}`（`xxd -i` 内嵌） |
| daemon socket | `/tmp/yabai_<user>.socket`（注意与 SA socket 区分） |

## CLI（daemon 侧）

| 命令 | 作用 |
|---|---|
| `yabai --load-sa` | 安装/更新 SA（版本不匹配 → 重装 payload + 重启 Dock；**AI 不代执行**） |
| `yabai --uninstall-sa` | 卸载 SA |
| `yabai --restart-service` | 重启 yabai 服务（涉及 Accessibility 授权，**用户执行**） |

## 属性位与版本（macOS 27.2，2026-10-28）

| 项 | 值 | 说明 |
|---|---|---|
| `OSAX_ATTRIB_REQUIRED` | `ADD_SPACE \| REM_SPACE \| MOV_SPACE` | daemon 握手只校验必需子集；可选位缺失不判负 |
| `OSAX_ATTRIB_ADD_SPACE` | 0x04 | 需 Dock create helper + Swift String 桥 + `__swiftEmptyArrayStorage` 三者齐全才上报 |
| `OSAX_ATTRIB_REM_SPACE` | 0x08 | 27.2 由 `CGSSpaceDestroy` 实现，仍上报 |
| `OSAX_ATTRIB_MOV_SPACE` | 0x10 | 27.2 由 `CGSMoveManagedSpaceToDisplayIndex` / `SLSTransaction*` 实现，仍上报 |
| `OSAX_VERSION` | **2.1.41** | 7.2.13；payload 任一次改动都要 bump（R15） |
| 27.2 解析项 | Spaces 槽 `0x329be0` / create helper `0x20ce00` / 空数组槽 `0x2ef0d8` | 构建锁定 + 段范围校验；27.2 上旧 pattern 全部 0 命中 |
| Dock 构建白名单 | `2571.0.6.402`（27.0/27.1）、`2571.1.32.402`（27.2） | 未知构建拒绝初始化（fail-closed） |
