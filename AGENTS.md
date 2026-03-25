# AGENTS.md - Project Memory & Behavioral Constraints

> Maintained by AI. Do not edit manually.

## Core Rules

### R1: Session Initialization

On every session start, immediately read all files under `memory-bank/`.
Create from template if missing.

### R2: Memory Update (Enforced)

#### Trigger Mapping

| Trigger              | Update File         | Content                          |
|----------------------|---------------------|----------------------------------|
| Code change          | activeContext.md    | Specific change + date prefix    |
| Task completed       | progress.md         | Move to "Completed"              |
| Architecture decision| systemPatterns.md   | New pattern / design decision    |
| Toolchain change     | techContext.md      | Dependency / version change      |
| API/feature change   | README.md           | Milestone update                 |
| Rule refinement      | AGENTS.md           | Rule addition / correction       |

#### Update Format
```
- [YYYY-MM-DD] - Change Title
  - File: specific modification
  - Impact: business/system impact
```

### R3: System-Level Red Lines（系统级红线）

这个项目涉及 macOS 私有框架和内核接口，以下操作**绝对禁止**未经确认擅自执行：

- **禁止**修改任何涉及 `scripting-addition` 注入逻辑的代码
- **禁止**修改 SkyLight 私有 API 的调用签名或参数（可能导致系统崩溃）
- **禁止**擅自变更 `mach_msg` / Mach Port 权限相关代码
- **禁止**在未理解窗口树完整遍历逻辑前修改 `window_manager` 核心结构
- **禁止**擅自变更 `makefile` 中的 codesign entitlements
- **禁止自动重启 yabai 进程**：yabai 的启动涉及 Accessibility 权限授权、scripting-addition 注入 Dock.app 等需要人工交互的步骤。AI 执行 `yabai --restart-service` 或任何形式的进程重启后，无法感知授权弹窗是否出现、注入是否成功，极易误判为「重启失败」并陷入反复重试循环，造成系统环境污染。**任何需要重启 yabai 的操作，必须明确告知用户手动执行，AI 只输出命令，不执行。**

### R4: Build System Awareness

**必须读取** `makefile` 了解当前构建目标、entitlements 和 codesign 配置。
不质疑、不建议修改构建链，除非用户明确要求。

### R5: Git Commit Authorization (Enforced)

**单次交互授权原则**：commit 授权仅对当前明确变更有效。

| Operation              | Authorization Lifetime | Notes                    |
|------------------------|------------------------|--------------------------|
| git commit/push        | Current change only    | Per-change authorization |
| git status/log/diff    | No auth needed         | Read-only                |
| git branch (create)    | One-time               | No subsequent commit     |

**Trigger Keywords**：「提交」/「commit」/「推送」/「push」/「提交并推送」

**Red Lines**：
- ❌ 模糊话术（「可以」「没问题」「审查通过」）≠ 授权
- ❌ 授权 A 变更 ≠ 授权 B 变更

### R6: Technical Decision Confirmation

**禁止擅自决策**：
- C 标准版本（C99/C11/C17）
- 私有 API 引用方式（header 声明 vs 动态查找）
- 内存管理策略（arena allocator vs malloc）
- IPC 协议格式变更（可能破坏 yabairc 脚本兼容性）

原则：**只读不猜，只实现不决策，有疑问必须问。**

### R7: Boundary Principles

- **不懂就问**：涉及 Mach 内核、SkyLight 私有 API、WindowServer 行为时，不确定必须停下来问用户，禁止凭"印象"实现
- **变更溯源**：发现与记忆不一致时，优先 `git log` 确认，而非断言「AI 记错了」
- **验证优先**：私有 API 行为先在 `tests/` 中验证再使用

### R8: Code Standards

- **Language**: All code/comments/logs in English; `.md` files may use Chinese
- **Style**: Follow existing codebase conventions (K&R brace style, snake_case)
- **Memory**: Explicit ownership via comments when non-obvious; RAII not available in C, document alloc/free contracts on every non-trivial function
- **No Warnings Policy**: Code must compile clean under `-Wall -Wextra -Werror`
- **Comment Philosophy** (Clean Code adapted for C):
  - ✅ Function contracts (pre/post conditions for non-trivial logic)
  - ✅ Why comments for Mach/SkyLight workarounds
  - ❌ What comments (code should self-explain)
  - ❌ Commented-out code blocks

### R9: Task Planning (Enforced)

Multi-step tasks (3+ steps) must use a todo list before execution.
Clean up todo list after completion.

### R10: File Management (Enforced)

- ❌ No temporary log/txt/tmp files
- ✅ Pipe output directly to console
- Post-task checklist: any unintended files created? clean up immediately.

### R11: Dependency Management (Enforced)

No new system frameworks or third-party libraries without explicit user approval.
Must provide: purpose, rationale, impact assessment, alternatives.

### R12: Memory File Maintenance (Enforced)

| File                | Max Lines | Overflow Policy              |
|---------------------|-----------|------------------------------|
| activeContext.md    | 150       | Keep last 30 days            |
| progress.md         | 100       | Archive completed items      |
| systemPatterns.md   | 80        | Merge similar patterns       |
| techContext.md      | 80        | Remove stale configs         |
| projectbrief.md     | 50        | Keep concise                 |

### R13: AGENTS.md Self-Update (Enforced)

Trigger: rule violation found, user adds constraint, repeated error needs fixing.
Flow: document problem → add/modify rule → record in activeContext.md → await confirmation.

## Execution Flow

```
Session start → Read memory-bank/ → Create todo (if needed)
↓
Process request → Clean temp files → Update memory (R2)
↓
Check line counts (R12) → Prune if needed → Output summary
```

## Memory Bank Structure

`memory-bank/` directory:
- `projectbrief.md` - Core project goals & architecture scope (≤50 lines)
- `techContext.md` - Toolchain, private APIs, SIP requirements (≤80 lines)
- `systemPatterns.md` - Design patterns: event loop, window tree, IPC (≤80 lines)
- `activeContext.md` - Current work focus (≤150 lines)
- `progress.md` - Task progress (≤100 lines)