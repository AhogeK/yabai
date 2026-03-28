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
| Phase 28 | ⏳ PENDING | 等待用户测试 |

---

## 待用户执行

**根据 AGENTS.md R3，AI 禁止自动重启 yabai**

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