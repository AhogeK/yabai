# AGENTS.md - Project Memory & Behavioral Constraints

> Maintained by AI. Do not edit manually.

**所有的修改行为，逻辑决策，思考方向之类的内容都要所有记录，让AI的行为不管在任何session，不管是否被压缩都能可回溯**

## Core Rules

### R1: 会话初始化（渐进式加载）

每次会话开始立即读取：

1. `AGENTS.md` - 项目规则与约束（MUST READ FIRST）
2. 时间线层：`memory-bank/activeContext.md` + `memory-bank/progress.md`（缺失则按结构创建）

**领域文件按任务相关性加载，不一次性全读**（大型系统的有效注意力是稀缺资源）：

| 任务类型 | 需加载 |
|---|---|
| 系统升级后 SA 失效 / pattern 维护 / 定位新入口或单例 | `domains/dock-reverse-engineering/` |
| 改 SA 能力、协议、属性位；排查握手/注入 | `domains/scripting-addition/` |
| space 生命周期（create/destroy/move/focus）行为异常 | `domains/space-management/` |
| 跨领域任务（如空间创建同时涉及定位与协议） | 先读 `domains/README.md` 路由，再按需展开 |

`systemPatterns.md`（横切结构）、`techContext.md`（环境与 ABI）、`projectbrief.md` 在需要时读取。

**回源原则**：不同事实回不同来源——当前 binary 行为以**实测**为准，代码契约以**源码**为准，历史原因以 `docs/` 证据链为准；不得用记忆替代实测。

### R2: 记忆更新（强制实时）

**严禁滞后更新**——不在本次响应内落盘 = 下一次会话断片。响应结束前**必须**完成评估与写入（含"本次无更新"的显式判断）。

**更新前置（BEFORE）**：任何代码修改或任务执行前，先读 `AGENTS.md` + `activeContext.md` + `progress.md`。

**触发映射（AFTER）**：

| 触发条件 | 更新文件 | 更新内容 |
|---|---|---|
| 代码/脚本修改 | `activeContext.md` | 具体变更 + 日期前缀 |
| 任务完成 / 阶段推进 | `progress.md` | 完成项归档、当前阶段变更 |
| 架构 / 逆向决策 | `systemPatterns.md` | 新模式、设计决策 |
| 工具链 / 私有 API / 偏移变化 | `techContext.md` | 依赖、偏移表、SIP 要求 |
| 面向用户的文档 / 里程碑 | `README.md` | 功能/版本/使用方式 |
| 规则增改 | `AGENTS.md` + `activeContext.md` | 规则正文 + 变更记录（R13） |

**格式**：

```
- [YYYY-MM-DD HH:MM] - 变更标题
  - File: 具体修改
  - Impact: 系统/业务影响
```

**校验**：写入后执行 `git diff --stat`，确认记忆记录与实际改动一致；不一致以实际改动为准并补记。

### R3: 系统级红线（macOS 私有接口）

这个项目涉及 macOS 私有框架和内核接口，以下操作**绝对禁止**未经确认擅自执行：

- **禁止**修改任何涉及 `scripting-addition` 注入逻辑的代码
- **禁止**修改 SkyLight 私有 API 的调用签名或参数（可能导致系统崩溃）
- **禁止**擅自变更 `mach_msg` / Mach Port 权限相关代码
- **禁止**在未理解窗口树完整遍历逻辑前修改 `window_manager` 核心结构
- **禁止**擅自变更 `makefile` 中的 codesign entitlements
- **禁止自动重启 yabai 进程**：yabai 的启动涉及 Accessibility 权限授权、scripting-addition 注入 Dock.app 等需要人工交互的步骤。AI 执行 `yabai --restart-service` 或任何形式的进程重启后，无法感知授权弹窗是否出现、注入是否成功，极易误判为「重启失败」并陷入反复重试循环，造成系统环境污染。**任何需要重启 yabai / 重装 SA / 重启 Dock 的操作，必须明确告知用户手动执行，AI 只输出命令，不执行。**

### R4: 构建系统认知

**必须读取** `makefile` 了解当前构建目标、entitlements 和 codesign 配置。不质疑、不建议修改构建链，除非用户明确要求。

- 构建验证命令：`make BUILD_PATH=<临时目录>`（避免覆盖用户已安装的 `~/.local/bin/yabai`）；**首次需先 `mkdir -p <BUILD_PATH>/yabai_bin`**，否则 `xxd` 输出失败
- 若 `xcrun clang` 报 Xcode license 未接受，可临时用 `DEVELOPER_DIR=/Library/Developer/CommandLineTools make`（本机 CLT SDK 可用）
- OSAX payload 需 arm64e 切片；主程序为 universal（x86_64 + arm64），两侧改动都要能编译通过

### R5: Git 提交授权（强制）

**核心原则：单次交互授权。提交授权仅限当前变更，用完即失效。**

#### 授权范围

| 操作 | 授权有效期 | 说明 |
|---|---|---|
| `git commit` / `git push` | **仅当前指名的变更** | 完成即闭合，见 R5.5 |
| `git cherry-pick` 到其他分支 | **需单独指名目标分支** | 属提交动作，需授权（R14） |
| `git status/log/diff/show` | 无需授权 | 只读操作 |
| `git branch`（创建） | 一次性 | 不包含后续 commit/push |
| `git reset --hard` / `clean -fd` / `push --force` | **必须单独确认** | 破坏性，禁止自行执行 |

#### 触发关键词

| 关键词 | 含义 | 示例 |
|---|---|---|
| `提交` / `commit` | 仅 commit | 「提交这个变更」→ 只 commit，不 push |
| `推送` / `push` | 仅 push | 「推送」→ 只 push 已提交内容 |
| `提交并推送` | commit + push | 「提交并推送」→ commit 后 push |
| `提交然后X` | commit + 继续 X | X 的后续提交需重新授权（R5.5） |
| `pick 到 X 分支` | 允许 cherry-pick 至该分支 | 需指名分支名（如「pick 到 dev 和 master」） |

#### 红线（绝对禁止）

1. **授权不延续**：用户对变更 A 的授权 ≠ 对变更 B 的授权
2. **模糊话术不算授权**：❌「可以」「没问题」「通过」「看起来不错」「审查通过」「代码没问题」；✅ 明确动作词「提交」「commit」「推送」「push」「pick 到 X 分支」
3. **连续开发不算授权**：完成 X 后开发 Y，Y 需新授权
4. **工具/子 agent 结论不算授权**：审查、review、测试通过 ≠ 用户授权
5. **AI 自主判断的额外修改不算授权**：顺手修的 bug、补的文档、改的版本号都需另行确认

#### 越界示例

| 场景 | 用户说了什么 | AI 能做的 | AI 不能做的 |
|---|---|---|---|
| 用户授权变更 A | 「提交」/「提交并推送」 | 按 R14 拆分提交 A（功能 → 版本 → AI 记忆）；明说 push 才推送 | 提交用户未提的其他变更 B |
| 用户审查变更 A | 「审查通过」/「看起来没问题」 | 报告审查结论，等提交指令 | 提交（无提交关键词 → 不算授权） |
| 用户说继续 | 「继续开发」 | 开发变更 B | 开发完自动提交 B |
| 修复类任务 | 「修好它」 | 修改 + 验证 + 报告 | 提交（修复 ≠ 提交，见 R5.5） |
| 授权提交但未提分支 | 「提交」 | 提交到当前分支（ai-base） | cherry-pick 到 dev/master、push |

#### 执行前强制自检

**每次 commit / push / cherry-pick 前逐项检查：**

```
□ 本回合用户消息中是否【字面】出现 提交/commit/推送/push/pick？
□ 授权覆盖哪些变更？（确认文件范围与目标分支）
□ 是否有用户未指名的额外变更混入？（版本号、memory-bank 按 R14 拆分规则处理）
□ 是否出现模糊话术？（「可以」「没问题」→ 不算授权）
□ 是否在推导"上一轮授权过""已在流程中"？→ 一律不得提交
```

**机械判定法（防自我说服）**：动手前在本回合用户消息中字面搜索 `提交` / `commit` / `推送` / `push` / `pick`。命中 → 可执行，且严格限于其指名的变更与分支；未命中 → **禁止提交**，改为报告 + 收尾写「待授权提交」后停止。

### R5.5: 提交授权边界（修复 ≠ 提交、授权作用域闭合）

**核心原则：「修好它」授权的是修改动作，不是提交动作。** 修改完成 ≠ 可以 commit。

常见误判（全部 ❌ 不算提交授权）：审查发现问题的修复指令、多轮修复中途的「继续修」、自主判断的补丁、「继续实施下一阶段」等前瞻指令。

**授权作用域闭合（强制）**：一条消息里的提交/推送指令，只覆盖该消息**指名的那些变更与分支**，执行完毕**立即闭合**。

| 消息 | 授权范围 | 闭合点 |
|---|---|---|
| 「提交这个变更」 | 仅该变更 | 提交后闭合 |
| 「提交并推送，然后继续开发 X」 | 该变更的 commit + push | **push 后闭合**；X 开发完需重新授权才能提交 |
| 「除 AI 内容外都 pick 到 dev、master」 | 两分支的 cherry-pick | pick 完成后闭合，不含推送（除非明说） |

修复/实施完成后的正确收尾：**报告内容 + 验证结果 + 「待授权提交」+ 停**。

### R6: 技术决策确认

**禁止擅自决策**：

- C 标准版本（C99/C11/C17）
- 私有 API 引用方式（header 声明 vs 动态查找 vs dlsym）
- 内存管理策略（arena allocator vs malloc）
- IPC 协议格式变更（可能破坏 yabairc 脚本兼容性）
- 逆向实现代际选择（沿用旧机制 vs 换用新入口）

原则：**只读不猜，只实现不决策，有疑问必须问。**

### R7: Boundary Principles

- **不懂就问**：涉及 Mach 内核、SkyLight 私有 API、WindowServer 行为时，不确定必须停下来问用户，禁止凭"印象"实现
- **讨论信号**：用户提出「为什么 / 能不能 / 是否应该 / 你看呢 / 是不是…更好」= 讨论与确认信号，先给分析 + 方案，**确认后才实施**；严禁把质疑性提问当作实施指令
- **变更溯源**：发现与记忆不一致时，优先怀疑"被用户或其他分支改过"，而非断言「AI 记错了」
  1. `git log` / `git diff` 确认变更来源与分支
  2. 验证当前逻辑是否正确（能跑通 = 逻辑成立）
  3. 若是用户改的 → 更新记忆适应新逻辑，**不要**恢复"旧版本"
  4. **禁止**揣测性结论（"这应该是错的"）
- **验证优先**：私有 API 行为先验证（静态 pattern 唯一性 / LLDB / 最小复现）再使用

### R8: Code Standards

- **Language**: All code/comments/logs in English; `.md` files may use Chinese
- **Style**: Follow existing codebase conventions (K&R brace style, snake_case)
- **Memory**: Explicit ownership via comments when non-obvious; RAII not available in C, document alloc/free contracts on every non-trivial function
- **No Warnings Policy**: Code must compile clean under `-Wall -Wextra`
- **Comment Philosophy** (Clean Code adapted for C):
  - ✅ Function contracts (pre/post conditions for non-trivial logic)
  - ✅ Why comments for Mach/SkyLight workarounds
  - ❌ What comments (code should self-explain)
  - ❌ Commented-out code blocks
- **编辑前验证（强制）**：先读完整文件（片段读取不足时直接整文件读取，不反复片段读同一文件）→ 编辑后编译验证（`make`）→ 涉及 SA 行为改动时说明静态/动态验证路径
- **asm 宏注意**：内联汇编的操作数名不得与宏参数同名（预处理器替换会导致 `%[name]` 失配）；单块 `asm volatile` + 完整 clobber（含 `memory`）

### R9: Task Planning (Enforced)

Multi-step tasks (3+ steps) must use a todo list before execution. Clean up todo list after completion.

### R10: File Management (Enforced)

- ❌ No temporary log/txt/tmp files；❌ 禁止重定向落盘（`> output.log`）——输出到控制台或系统 `/tmp/<topic>/`
- ✅ 分析中间产物放系统临时目录（仓库外），任务结束清理
- Post-task checklist: any unintended files created? clean up immediately.
- 占用资源的长驻进程（调试器、服务、监视器）用完即关

### R11: Dependency Management (Enforced)

No new system frameworks or third-party libraries without explicit user approval.
Must provide: purpose, rationale, impact assessment, alternatives.
红线：禁止冗余依赖、禁止重复功能包、优先复用现有依赖与既有逆向机制。

### R12: 记忆文件维护（强制 - 冷热分层）

**核心原则：修剪 = 归档而非删除。** memory-bank 是项目记忆，历史条目即使当前不用也可能被回溯（排障、版本对比、模式复用）。

| 文件 | Max Lines | 超限处理 |
|---|---|---|
| `activeContext.md` | 150 | 早于 30 天的条目按月移入 `memory-bank/archive/activeContext-YYYY-MM.md` |
| `progress.md` | 100 | 已完成项移入 `archive/progress-YYYY-MM.md` |
| `systemPatterns.md` | 80 | 合并相似模式；被合并的旧模式移入 archive |
| `techContext.md` | 80 | 移除/归档过时配置（含旧系统版本偏移表） |
| `projectbrief.md` | 50 | 保持精炼 |

**归档操作**：
1. shard 文件只增不改，头部带注释 `> 冷数据归档（R12）。仅供回溯，不再更新。`
2. 归档后 `activeContext.md` 末尾保留归档指针
3. 完整性校验：归档前后总行数差 = 新增 shard 头行数（零丢失）
4. 超限但无 30 天外条目时：**压缩措辞**而非删内容；仍超限则提出阈值修订（R13），不得靠删记忆达标

**分层原则**：时间线（本规则）回答"最近发生了什么"；跨轮次可复用的判断进领域层（R19）。

### R13: AGENTS.md Self-Update (Enforced)

Trigger: 规则漏洞 / 用户新约束 / 重复错误需固化。
Flow: 记录问题 → 添加/修改规则 → 记录到 `activeContext.md` → 等待用户确认。
命名：新增用 `R{n}`，紧邻主题可用 `R{n}.{m}`；修改保留序号并注明版本；废弃标记 `[已废弃]`。

### R14: 分支管理与提交拆分（强制 - 三级 cherry-pick）

**核心原则：只能 cherry-pick，逐级 `ai-base → dev → master`；严禁 merge/rebase/反向 pick。**

| 分支 | 角色 | 允许内容 | 禁止内容 |
|---|---|---|---|
| `ai-base` | AI 工作分支（默认 checkout） | 业务代码 + 版本号 + AI 文件（`memory-bank/`、`docs/reverse-engineering-*`、`skills-lock.json`、`AGENTS.md`） | —— |
| `dev` | 开发分支 | 业务代码 + 版本号 + 面向用户的项目文档（如 `docs/upstream-sync-report-*`） | AI 文件（memory-bank、逆向笔记、AGENTS.md、skills-lock.json、`.omo/`） |
| `master` | 发布分支 | 与 `dev` 内容一致 | 同 `dev`；且禁止直接改代码 |

**提交拆分（原子化，顺序固定）**：

1. **功能 commit**：仅业务代码（`src/`、`scripts/`、`makefile`），不含版本号文件
2. **版本 commit**：`src/yabai.c`(PATCH) + `scripts/install.sh`(VERSION) + `src/osax/common.h`(OSAX_VERSION) + `CHANGELOG.md` + `doc/yabai.1`（日期）
3. **AI 记忆 commit**：`memory-bank/` + `AGENTS.md` + AI 逆向笔记 —— **只进 ai-base**

提交信息：`fix(osax): 根因+修复+验证` / `chore: bump version to X.Y.Z` / `docs: …`

**同步操作与校验**：

```bash
git checkout dev    && git cherry-pick <fix> <bump>
git checkout master && git cherry-pick <dev's fix> <dev's bump>   # 逐级，取 dev 的 commit
git checkout ai-base
```

校验清单（每次 pick 后逐项确认）：

- [ ] `git diff <branch> <branch> -- src/osax` 为空（代码一致）
- [ ] `git diff --stat dev master` 为空（两分支工作树一致）
- [ ] `git ls-tree -r --name-only dev | grep -E "^(memory-bank|skills-lock)"` 无输出
- [ ] 三支版本号一致（`PATCH` / `VERSION` / `OSAX_VERSION`）
- [ ] 推送后 `git fetch origin` + 逐支比对 `local == origin/<branch>`

**禁止操作**：merge、rebase、`git reset --hard`、反向 cherry-pick（master→dev）、在 dev/master 直接提交代码、把 AI 文件带进 dev/master。

**事故恢复**：立即停止 → 确认污染范围（`git log --oneline` / `git diff`）→ 回到安全点 → 重新 pick → 需强推时先取得用户同意（`--force-with-lease`）→ 记录到 `activeContext.md`。

### R15: 版本号管理（强制实时）

**核心原则：任何代码变更必须同步更新版本号，严禁滞后、跳号。**

版本号位置（改一处必查全部）：

| 位置 | 字段 | 说明 |
|---|---|---|
| `src/yabai.c` | `MAJOR/MINOR/PATCH` | 主程序版本 |
| `scripts/install.sh` | `VERSION="X.Y.Z"` | 安装脚本版本 |
| `src/osax/common.h` | `OSAX_VERSION` | scripting-addition payload 版本（payload 有改动才 bump） |
| `CHANGELOG.md` | `## [X.Y.Z] - YYYY-MM-DD` | 新增条目（Fixed/Added/Changed） |
| `doc/yabai.1` | `Date:` / `.TH` 日期 | 手册日期 |

规则：Bug 修复 → PATCH+1；新功能 → MINOR+1；破坏性变更 → MAJOR+1。
禁止：代码变更不更新版本、硬编码散落版本号、版本 commit 早于功能 commit。

### R16: 上游与关联仓库只读

- `upstream`（asmvik/yabai）**只 fetch + 只读比对**：同步上游用 cherry-pick 进来，保留我们的版本号与分支结构；**禁止** push upstream、禁止改写其历史
- 其他关联仓库（如 `../ctt-server`、`../code-time-tracker`）**只读**：需要契约/行为时读源码验证实际行为，不猜测接口形状；**禁止**修改其中任何文件（含源码/测试/文档/版本号）
- 需要对方配合 → 以**需求文本**提出（现状 / 期望行为 / 理由 / 影响面），由用户决策

### R17: AI 产物与边界（强制）

- **`.agents/`（skills 工作区）只读红线**：禁止读取/修改/删除其中任何文件，禁止因"发现问题"改动，禁止纳入审查/重构范围；发现问题只提醒用户
- **AI 运行时数据**（`.omo/`、`.opencode/node_modules/` 等已 gitignore）不进提交
- **AI 逆向笔记/报告**：放 `docs/`（仅 ai-base 分支，见 R14）；面向用户的项目文档才允许进 dev/master
- **临时中间产物**：系统 `/tmp/<topic>/`，禁止落进仓库
- **未经用户同意不新增 `.md` 文档**（`AGENTS.md` 自更新除外）

### R18: 自我学习（skills 沉淀）

触发条件：同一问题解决 2 次以上，或单次排查 > 30 分钟且有复盘价值。
流程：**先询问用户**是否沉淀 → 同意后用 skill-creator 创建 → 写入 `.agents/skills/`。
禁止：自动写入 `.agents/`；未经确认把一次性结论固化成 skill；skill 属 AI 工作区，不触发项目版本号（R15）。

### R19: 领域知识库（强制）

**核心原则：知识按「领域」沉淀，不按「时间」堆积。** 领域专属的判断/契约/不变量不得只留在线性时间线里；固定结构的价值是**知识覆盖约束**（告诉 AI 至少必须理解哪些方面），而检索只能给出"可能相关"。

**第一层永远是领域**（业务/技术能力面，如 `dock-reverse-engineering`、`scripting-addition`、`space-management`），禁止按文档类型建第一层。

**每领域五件套**（缺一不可，建立即填实，禁止占位）：

| 文件 | 职责 | 内容要求 |
|---|---|---|
| `meta.md` | 领域边界、代码入口、术语 | 必须含**别名与易混概念**（同物多名 / 同名异物），只看这一个就知道"归哪、从哪看起" |
| `principles.md` | 不变量与第一性原理 | 能用来裁决新情况；写"为什么"，不写操作步骤 |
| `scenarios.md` | 触发场景 → 判断 → 动作 | 遇到 X 该怎么做，不用重新推理；含排查顺序 |
| `practices.md` | 具体做法、命令、参数、踩坑 | 可直接照做；**必须含反例与"为什么"** |
| `references.md` | 契约、偏移/符号表、端点、路径 | 事实性查表，不含判断；**不复制他域完整知识**，只留引用 |

**条目元数据（强制）**：每个领域文件头部标注知识状态，供系统升级后判定是否过期：

```
> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402
> **最后验证**：2026-09-15 · **状态**：已验证 | 含推论 | 方法论
> **来源**：<命令 / 源码位置 / 文档链接>
```

- `已验证` = 本机实测或源码逐项核对；`含推论` = 有推理成分、**未**现场验证；`方法论` = 跨版本稳定，不随版本失效
- 正文中的单条结论若为推论，须就地标注（如 `[推论]`），**不得把推断伪装成事实**；未知项显式登记为待确认

**写回规则**：`docs/` 是证据链（逆向过程、LLDB 输出、日志），**确认后的结论必须写回领域文件**，不得只留在 docs 或时间线。

**维护触发（代码/系统变化 → 必须复核的领域文件）**：

| 变化 | 需复核 |
|---|---|
| macOS 大版本升级 | **全域复核**（先 `dock-reverse-engineering/`，再 `space-management/principles.md` 代际表） |
| `src/osax/arm64_payload.m` / `x64_payload.m`（offset/pattern） | `dock-reverse-engineering/references.md`、`scenarios.md` |
| `src/osax/payload.m`（能力、握手、日志） | `scripting-addition/{principles,references,practices}.md` |
| `src/osax/common.h`（OSAX_VERSION / 属性位 / opcode） | `scripting-addition/references.md` |
| `src/sa.[hm]`（daemon 侧能力） | `scripting-addition/practices.md`、`space-management/references.md` |
| `src/space_manager.c` / `display_manager.c` | `space-management/{principles,scenarios}.md` |

**生长规则**：按需建档（宁可少而实，禁止为凑结构建空领域）；新知识先归类再更新对应文件；`memory-bank/domains/README.md` 索引必须与目录同步；横切规范留 `systemPatterns.md` / `techContext.md`，领域专属判断进领域文件，**不得两处重复**。

**红线**：❌ 占位文件 / `TODO: fill` / 空章节 ❌ 把领域文件当 changelog 用（版本流水账属 `progress.md`）❌ 与代码/契约不一致的表述（涉契约先只读核对源码）❌ 无元数据的领域文件；单文件 ≤200 行。

## Execution Flow

```
会话开始 → R1 读 AGENTS.md + memory-bank/
↓
处理请求（多步任务先 todo：R9；讨论信号先确认：R7）
↓
代码修改（编辑前读全文、编辑后编译验证：R8；边界内不猜测：R6）
↓
更新记忆（R2）+ 行数检查/归档（R12）+ 跨轮次判断沉淀领域（R19）
↓
清理临时文件与长驻进程（R10）
↓
提交（需授权：R5 / R5.5）→ 拆分与分支同步（R14）→ 版本号（R15）
↓
输出摘要（变更 / 验证证据 / 待授权事项）
```

## 约束

1. 文件读写由 AI 自主完成
2. 记忆文件行数受 R12 约束
3. 只记录已发生事实，不猜测
4. 变更即时更新（R2）
5. 项目一致性优先：新增前先 grep 现有模式，复用既有实现而非另起一套（有冲突先停下来问）
6. 编辑前必须读全文件，编辑后必须编译验证（R8）
7. 提交前必须完成自检 + 分支拆分（R5 / R14）
8. 截图保存至 `/Users/ahogek/Pictures/screenshots`

## Memory Bank Structure

**时间线层**（回答"最近发生了什么"）：

```
memory-bank/
├── projectbrief.md      核心目标与架构范围（≤50 行）
├── techContext.md       工具链、私有 API、当前系统版本偏移表、SIP 要求（≤80 行）
├── systemPatterns.md    横切设计模式：事件循环、窗口树、IPC、注入流程（≤80 行）
├── activeContext.md     当前工作焦点（≤150 行）
├── progress.md          阶段进度（≤100 行）
└── archive/             冷数据归档（R12，唯一豁免行数限制；按需创建，禁止建空目录）
    ├── activeContext-YYYY-MM.md
    └── progress-YYYY-MM.md
```

**领域层**（回答"这里什么是真的、该怎么做"，R19 治理）：

```
memory-bank/domains/
├── README.md                        领域索引（与目录同步）
├── dock-reverse-engineering/        Dock/框架逆向：pattern、偏移、动态定位
├── scripting-addition/              SA payload/loader、socket 协议、握手属性
└── space-management/                空间创建/销毁/移动/聚焦语义与实现代际
    └── 每领域五件套：meta.md / principles.md / scenarios.md / practices.md / references.md
```

## Quick Reference Card

| 阈值 | 要求 |
|---|---|
| 3+ 步骤 | 先建 todo（R9） |
| 记忆文件超行数 | 归档而非删除（R12） |
| 跨轮次可复用的判断 | 沉淀到领域文件（R19），不留在时间线 |
| 代码变更 | 版本号同步 + 编译验证（R15 / R8） |
| 提交/推送/pick | 当次授权 + 自检 + 分支拆分（R5 / R14） |
| 修复类任务完成 | 报告 + 「待授权提交」后停（R5.5） |
| 涉及私有 API / 内核 | 先问再做（R3 / R6） |
