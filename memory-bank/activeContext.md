# Active Context - yabai

## Current Work Focus

**macOS 26 Space Creation - Phase 30: 代码和文档库已完全净化**

---

## ✅ 代码清理完成 (2026-03-29 00:05)

**已删除** (~592 行)：
- 所有 `debug_log()` 调用
- 所有 `NSLog` 调试语句
- 所有 `hooked_` 函数
- 所有 hook 基础设施
- `attempt_eager_manager_capture()`
- `get_wallpaper_manager_for_create()`
- 所有 wallpaper manager hooks
- 所有 space creation entry hooks
- 所有 notification hooks
- `/tmp/yabai-sa-debug.log` 写入代码

**文件变化**：
- `payload.m`: 1858 行 → 1266 行
- `arm64_payload.m`: 保留核心宏定义
- `makefile`: 删除 `-framework AppKit`

## ✅ 文档清理完成 (2026-03-29 00:15)

**已删除** (13 个文件)：
- `lldb-output.txt`, `02-static-analysis.md`, `04-experiment-log.md`
- `all-lldb-debug-log.txt`, `architect-review-2026-03-28.md`
- `architect-review-request-2026-03-27.md`, `dtrace-space-precise.d`
- `dynamic-analysis-report-2026-03-28.md`, `LLDB-GUIDE.md`
- `OPERATING-GUIDE.md`, `plan-static-analysis-add-space.md`
- `space_debug.lldb`, `space-creation-impasse-analysis-report.md`
- `static-analysis-report-2026-03-28.md`

**保留** (核心分析文档)：
- ✅ `lldb-analysis.md` (74KB - 完整 LLDB 分析)
- ✅ `lldb-analysis2.md` (10KB - 第二次 LLDB 会话)

**构建结果**：✅ 编译成功，无警告

---

## Phase Status

| Phase | 状态 | 结果 |
|-------|------|------|
| Phase 1-3 | ✅ COMPLETE | 代码实现完成 |
| Phase 25-27 | ✅ COMPLETE | 清理完成 |
| Phase 27.1 | ✅ COMPLETE | Bug 修复（地址重复计算） |
| Phase 28 | ❌ FAILED | 测试失败 - 函数内部崩溃 |
| Phase 29 | ✅ COMPLETE | 宏修复（原子 asm + retain/release） |

---

## 测试结果 (2026-03-29 00:14)

**成功的部分**：
- ✅ `spaces_singleton=0x89ec901e0` 读取成功（非 nil）
- ✅ 地址计算正确
- ✅ 诊断日志打印正常

**失败的部分**：
- ❌ 没有 `space_create_entry returned` 日志
- ❌ 函数内部仍然崩溃

**根因分析** (架构师):
1. **宏分离问题** - `asm` + `((void(*)())func)()` 是两个语句，编译器可以中间插指令
2. **缺少 retain** - 原生调用有 `objc_retain`，我们直接传原始指针

**修复方案** (2026-03-29 00:35):
1. ✅ 合并到一个 `asm volatile` 块，使用 `blr` (寄存器间接跳转)
2. ✅ 添加 `objc_retain`/`objc_release` 包裹调用
3. ✅ 正确的 clobber 列表（所有 caller-saved 寄存器 + x30）

**测试成功** (2026-03-29 01:02):
```
[SPACE] singleton=0xc00870480 func=0x104c787d8
[SPACE] calling space_create_entry(display_id=1) retained=0xc00870480
[SPACE] space_create_entry returned  ← 第一次成功返回！
```
✅ Dock 不再崩溃
✅ space 创建成功
✅ 历史性突破！

```bash
# 1. 重启 yabai
yabai --restart-service

# 2. 等待 5 秒
sleep 5

# 3. 测试 space 创建
yabai -m space --create

# 4. 验证 Mission Control 中出现新 space
```

---

## 关键函数偏移 (macOS 26.4 Tahoe)

| 偏移 | 功能 | 状态 |
|------|------|------|
| `0x1f07d8` | 顶层创建入口 | 已实现，待验证 |
| `0x1eb33c` | 数组遍历 | 已确认 |
| `0x285564` | 空间处理 + CGS | 已确认 |
| `0x19e150` | DPPM 壁纸创建 | 已确认 |

---

## 相关文件

- `src/osax/payload.m` - 主 payload
- `src/osax/arm64_payload.m` - 偏移定义
- `docs/macos26/lldb-analysis.md` - LLDB 分析
- `docs/macos26/lldb-analysis2.md` - 第二次 LLDB 会话