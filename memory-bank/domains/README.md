# 领域索引（R19）

领域 = 跨轮次可复用的判断与契约。第一层永远是**能力面**，不是文档类型。
每个领域五件套缺一不可：`meta.md` / `principles.md` / `scenarios.md` / `practices.md` / `references.md`。
本索引必须与目录同步（R19）；按需建档，宁少而实，禁止空领域。

> **最后验证**：2026-09-15 · **状态**：已验证（与目录逐项比对）

| 领域 | 边界（一句话） | 何时来这里 |
|---|---|---|
| [`dock-reverse-engineering/`](dock-reverse-engineering/meta.md) | Dock.app / WindowManager.framework 的函数定位、pattern 维护与系统版本适配 | 系统升级后 SA 失效、pattern 0 命中、需要定位新入口/单例 |
| [`scripting-addition/`](scripting-addition/meta.md) | SA payload/loader 注入、socket 协议、握手属性与版本门 | 改 SA 能力、排查"payload 不支持本系统"、加 opcode |
| [`space-management/`](space-management/meta.md) | 空间的创建/销毁/移动/聚焦语义与三代实现 | `space --create/--destroy/--move/--focus` 行为异常 |

**与时间线层的分工**：`activeContext.md` / `progress.md` 记录"发生了什么"；领域文件记录"什么是真的、遇到 X 该怎么做"。同一事实只写一处（R19 红线）。
