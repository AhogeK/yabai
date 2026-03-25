---
description: 初始化会话 - 读取项目上下文（按 AGENTS.md R1 强制执行）
---

**⚠️ 强制规则**: 必须严格按照 AGENTS.md 执行，任何偏离视为违规。

## 执行流程

### 阶段 1: 读取核心约束

必须按顺序读取：

1. **行为约束** - @AGENTS.md（**优先读取，后续所有操作的准则**）
2. **项目记忆**:
   - @memory-bank/projectbrief.md
   - @memory-bank/techContext.md
   - @memory-bank/systemPatterns.md
   - @memory-bank/activeContext.md
   - @memory-bank/progress.md
3. **项目说明** - @README.md

缺失文件按 AGENTS.md 模板创建。

### 阶段 2: 读取构建与签名配置

**必须读取**：
- @makefile（构建目标、entitlements、codesign 配置）
- @.clangd（编译器标志、include 路径）
- @.gitignore

**核心原则**：只读取，不质疑构建配置。

### 阶段 3: 扫描代码结构

使用 Glob 工具扫描：
- `src/**/*.c` / `src/**/*.h`（核心源码）
- `tests/**/*`（测试文件）
- `scripts/**/*`（辅助脚本）
- `examples/**/*`（配置示例）

**禁止假设**：必须通过扫描确认文件实际存在。

### 阶段 4: 理解系统边界

读取完成后，必须确认以下边界（yabai 特有）：

1. **SIP 状态假设**：当前开发针对 SIP-disabled 还是 SIP-enabled 模式？
2. **私有 API 状态**：`src/` 中哪些头文件是私有 API 声明？是否有已知断裂风险？
3. **macOS 版本目标**：当前 `makefile` 的 deployment target 是什么？
4. **当前任务边界**：根据 activeContext.md 确认工作范围
5. **重启边界**：明确告知自己——任何涉及 yabai 进程重启的操作（包括
   `yabai --restart-service`、`brew services restart yabai`、
   kill 进程等），必须输出命令交由用户手动执行，AI 不得自行调用，
   不得在等待重启结果后自动判断成功/失败并重试。

### 阶段 5: 输出摘要

```
=== 项目状态 ===

项目: yabai - macOS Tiling Window Manager

构建配置:
- macOS deployment target: [from makefile]
- Codesign identity: [from makefile]
- Key entitlements: [list]

当前进度:
- [from progress.md]

正在处理:
- [from activeContext.md]

技术栈（按 techContext.md + makefile 确认）:
- C standard: [version]
- Private APIs in use: [list]
- SIP requirement: [enabled/disabled]

代码结构（按 Glob 扫描）:
- src/ 文件数: [count]
- 核心模块: [list key .c files]
- tests/ 状态: [exists/empty]

核心约束（按 AGENTS.md）:
- 系统级红线（R3）：私有 API / Mach Port / scripting-addition 修改需人工确认
- Git 操作需明确授权（R5）
- 构建链变更需人工确认（R4）
```

## 禁止事项

1. **质疑私有 API**：不说「SkyLight API 可能不稳定，建议换方案」
2. **质疑版本**：不说「C17 已过时」或「应该升级 macOS deployment target」
3. **主观评判**：不做「代码需要重构」等评价（review 任务除外）
4. **跳读 AGENTS.md**：未读取约束文件就开始操作
5. **假设 SIP 状态**：必须从 techContext.md 或 makefile 确认，不猜测

---

**场景区分**:
- `/boot` → 了解项目状态（客观陈述，不做评判）
- 用户要求 review → 审查代码质量（可做价值判断）