# principles — 逆向定位的不变量

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：方法论
> **来源**：26→27 两代适配实践；每条判据均有 `references.md` 中的命中证据

## 1. 稳定字节 vs 不稳定字节

| 稳定（用确定值） | 不稳定（用 `??`） |
|---|---|
| `pacibsp` = `7F 23 03 D5`（arm64e 叶子/非叶子函数锚点） | `bl` 目标偏移 |
| `stp/ldp` 的 opcode 与寄存器组合语义 | `adrp` 页偏移、栈帧大小 |
| 固定寄存器搬运（如 `mov x1, x30`） | 编译器寄存器分配、条件分支立即数 |

**推论**：pattern 的第一字节若落在**条件分支立即数**上（如 setFrontWindow 的 `cbz w1`），每次重编译都可能失配 → 首位应通配。

## 2. 先静态定位，后动态验证

Ghidra / otool / dyld_info 负责"找"，LLDB 只负责"证"。定位阶段不进调试器；两者冲突时以动态实测为准。

## 3. 不硬编码地址，能解码就解码

单例通过 `adrp+add` / `adrp+ldr` 指令对在运行时解码（`decode_adrp_add_pair` / `decode_adrp_ldr_pair`），不写死全局变量地址。

## 4. 全局单例的识别三要素

1. **语义画像**：该全局作为接收者出现的方法集合（Spaces ↔ `currentSpaceForDisplay:` / `allUserSpaces`；DPPM ↔ `addSpace:forDisplayUUID:` / `moveSpace:toDisplay:displayUUID:`）
2. **构造点**：写入该全局的代码（setter 的 `cbnz + str` 守卫是强指纹）
3. **引用计数调用点**：`bl objc_retain` + `mov x20, x0` 后紧随 `bl <某函数>` → 该函数以该单例为 Swift `self`

## 5. 基线窗口语义（最容易误判的一条）

`hex_find_seq(baseaddr + base, pattern)` 只在 `base` 起 `0x1286a0` 内取**首个**匹配。因此：

- 同一 pattern 有多处匹配时，**取窗口内第一个**——错的那处可能刚好在前
- 函数**上移/下移出窗口**表现为"0 匹配"，必须同步改 `base`，而不是改 pattern

## 6. 版本适配 = 全量重验，不是修报错点

新系统只报一个功能坏，但实际失效面通常是"**版本门 + 全部基线 + 全部 pattern**"。流程见 `scenarios.md`。

## 7. 证据优先

任何 offset/pattern 结论必须能复现：给出命中地址 + 解码出的目标 + 唯一性判定（0 = 错，1 = 对，多 = 太短）。
