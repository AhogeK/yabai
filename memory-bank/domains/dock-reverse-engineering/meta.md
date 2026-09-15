# meta — Dock / 私有框架逆向

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：环境基线
> **来源**：本机实测（macOS 27.0/Dock 2571.0.6.402）+ `docs/reverse-engineering-macos27-space-create.md`

## 边界

定位并维护 yabai scripting-addition 依赖的 Dock.app / 私有框架内部符号：

- 函数入口（`addSpace` / `removeSpace` / `moveSpace` / `setFrontWindow` / `space_create_entry`）
- 数据段单例全局（Spaces、DPPM、Dock 设置对象、热区控制器）
- 指令级补丁点（animation time 等）
- 跨系统版本的 pattern / 偏移适配

**不属于本领域**：SA 与 daemon 的协议（→ `scripting-addition/`）、空间语义与调用约定（→ `space-management/`）。

## 代码入口

| 位置 | 内容 |
|---|---|
| `src/osax/arm64_payload.m` | `get_*_offset()` / `get_*_pattern()`：按 macOS 主版本分支的全部定位基线 |
| `src/osax/x64_payload.m` | Intel 侧同名函数（仅 ≤15 及 26.4 Intel 分支） |
| `src/osax/payload.m` | `hex_find_seq` / `decode_adrp_add(_pair)` / `decode_adrp_ldr_pair` / `find_dppm_singleton_instructions` / `find_spaces_singleton_instructions` |
| `docs/reverse-engineering-*.md` | 各版本的完整逆向过程记录（证据链，非结论表） |

## 术语

| 术语 | 含义 |
|---|---|
| **基线（base offset）** | `hex_find_seq` 的搜索起点；实际 = `__TEXT.vmaddr + base` |
| **窗口（search window）** | 从基线起 `0x1286a0` 字节；**找不到 = 函数下移出窗口**，不是"函数不存在" |
| **pattern** | 带 `??` 通配的机器码字节串，匹配到的是**指令序列起点**（可能是函数入口，也可能是入口前 4 字节的 cbz 早退） |
| **DOUBLE-ANCHOR** | 先按 `bl <已知函数>` 定位调用点，再回溯最近的 `adrp+add` 得到单例全局 |
| **语义画像** | 用 `__objc_stubs` → selector 映射 + 寄存器级抽象解释，按"全局 × 方法名"矩阵判定全局变量的身份 |
| **代际（generation）** | 同一能力在不同 macOS 大版本的实现方式（如空间创建的三代） |

## 环境基线

| 项目 | 值 |
|---|---|
| 目标二进制 | `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock`（universal，取 **arm64e** 切片） |
| 框架 | `WindowManager.framework`（27+，**仅存在于 dyld shared cache**）、`DockCore`（26+） |
| 镜像基址 | `__TEXT.vmaddr = 0x100000000` |
| 关键工具 | `lipo` / `otool -tV` / `nm -u` / `dyld_info -objc,-fixups,-exports,-imports` / `xcrun swift-demangle` / Ghidra Headless |

## 别名与易混概念

| 易混对 | 区分 |
|---|---|
| pattern / 基线（base offset） | pattern = 带 `??` 的字节串；基线 = 搜索起点。**二者必须配套改**，只改一个会"假性 0 命中" |
| 函数入口 / 早退点 | 部分 pattern 匹配到的是入口前 4 字节的 `cbz`（setFrontWindow 即如此）：`w1 == 0` 时跳走，否则落入真正入口 |
| 全局变量 / 单例对象 | 全局是 `__common` 段的指针槽（文件里为 0）；单例是它运行时指向的对象 |
| "0 命中" / "函数不存在" | 函数下移出 `base + 0x1286a0` 同样表现为 0 命中；先怀疑基线再怀疑函数 |
| Dock.app / DockCore / WindowManager | 26 起部分逻辑在 DockCore 框架；**27 起空间与窗口管理在 WindowManager.framework**（仅存于 dyld shared cache） |
| arm64e / arm64 | 主程序为 arm64（universal）；SA payload 与逆向目标为 arm64e（含 PAC 指令） |
| 反汇编文本的 `literal pool for:` / `Objc cfstring ref:` | otool 注释，不是代码语义；定位时只作线索 |
