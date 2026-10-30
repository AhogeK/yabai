# Plan: macOS 原生全屏「记忆还原」（已退役）
> 修正记录二（2026-10-10，事故后）：`space_window_list()` 返回 `ts_alloc_*` **临时池**指针（`src/misc/ts.h`），对它 `free()` 会触发 libmalloc abort → daemon 被 launchd 反复拉起。修正版已删除全部 `free()`；并把 `space_manager_find_view`（会自动建 view）换成只读的 `space_manager_query_view`，避免为已销毁空间创建空 view。新增静态护栏：全仓库扫描"`space_window_list` 结果被 free"。

> **Status: retired (2026-10-30)**。macOS 更新后系统已能把窗口放回来源空间；本计划对应的
> `fullscreen_restore` / `view_follow` 代码已在 7.2.22（`9916eeb` / `c70160c`）删除。以下内容仅保留为历史证据。
- 7.2.22 branch sync: ai-base `9916eeb`/`c70160c`/`5685751`,
  dev `581aa39`/`c944278`, master `3f8cdfe`/`09ba6a6`.

> 修正记录（2026-10-10 实施中）：侧别捕获原计划读 `window->windowed_frame`，实测该字段仅由 yabai 自己的全屏切换维护，系统原生全屏（视频通话）路径下是陈旧值 → 改为滚动几何记忆，结论已就地更新。
Date: 2026-10-10 · Status: retired (2026-10-30) · 执行者：本会话（用户授权自行决策并实施）

## Objective

macOS 27.0.1 上，窗口进入原生全屏后退出时，系统会把整个显示器切回**该显示器第一个 user space**，窗口随之落到那里（S10 实测：`SPACE_CHANGED: 58 → 1526 → 50`，全程无 yabai 搬移指令）。本计划在 yabai 内加一层**短期记忆**：记录窗口进全屏前的来源空间与分屏侧别，在它被系统放回后将其送回来源空间，并把它恢复到原来那一侧（原本在右就回右侧）。

## Global Constraints

| 约束 | 值/来源 |
|---|---|
| 系统基线 | macOS 27.0.1 (26A434) · Dock 2571.0.6.402（`memory-bank/techContext.md`） |
| 代码标准 | 编译须在 `-Wall -Wextra` 下零告警；注释英文；K&R + snake_case（R8） |
| 红线 | 不改 SA 注入逻辑；不改 SkyLight 调用签名；不直接改 `window_node` 树结构（只用现成 warp/send 接口）（R3） |
| 版本号 | 新功能 → MINOR：7.1.29 → **7.2.0**；payload 未改 → OSAX 保持 2.1.33（R15） |
| 依赖 | 不引入任何新框架/库（R11） |

## Verified Facts

| 维度 | 实测值 | 来源 / 命中 |
|---|---|---|
| 移动窗口到空间的引擎 | `window_manager_send_window_to_space(sm, wm, window, dst_sid, false)` | `src/window_manager.c:2102` |
| 该引擎插入目标视图的位置 | 固定 `insertion_point = 0`（`space_manager_tile_window_on_space` → `..._with_insertion_point(...,0)`） | `src/space_manager.c`（两函数相邻） |
| 来源空间 | `g_space_manager.last_space_id` 在 `SPACE_CHANGED` 处理器内先赋值（进入全屏时 = 来源空间） | `src/event_loop.c:994` 起 |
| 全屏判定 | `space_is_fullscreen(sid)` / `window_is_fullscreen(window)` | `src/space.c:93` / `src/window.h:166` |
| 事件钩子 | `WINDOW_MOVED`(675) `WINDOW_DESTROYED`(603) `SLS_SPACE_DESTROYED`(980) `SPACE_CHANGED`(994) | `src/event_loop.c` |
| 树/几何可用信息 | `struct window{CGRect frame, windowed_frame}`；`struct view{root, insertion_point, layout}`；`struct window_node{parent,left,right,split,child}` | `src/window.h` / `src/view.h` |
| 位置交换手段 | `window_manager_warp_window(a,b)`：同父且 a 为单窗时交换两者树位置 | `src/window_manager.c` |
| 全屏空间事件实况 | 全屏空间 `id=1526` 只触发 `SPACE_CHANGED`（未见 `SPACE_CREATED`） | daemon 日志 2026-10-10 |
| 窗口移动事件实况 | 全屏进出两侧均出现 `WINDOW_MOVED: Discord 15973` | 同上 |

## Decision Ledger

| 项 | 状态 | 依据 |
|---|---|---|
| 还原触发点 = `SPACE_CHANGED` + `WINDOW_MOVED` 双钩 | ✅ decided | 全屏空间只发 CHANGED（日志）；窗口空间在系统侧异步落定，MOVED 兜底 |
| 记忆条目上限 8，超出丢最旧 | ✅ decided | 无定时器可用；条目在还原/窗口销毁/来源空间销毁时删除 |
| 侧别判定用几何（节点 `area`）而非树内遍历 | ✅ decided | 树字段可读但语义脆（zoom/stack）；节点 area 是 yabai 自己平铺出来的事实 |
| ~~侧别在进全屏时从 `window->windowed_frame` 读~~ → **改：滚动几何记忆** | ⚠️ 已修正 | 实测：`windowed_frame` 只在 `window_manager_toggle_window_fullscreen`（yabai 自己切全屏）里写入，系统原生全屏不会维护 → 原前提被推翻，改为在窗口仍在 user space 时滚动记录（`window_manager_remember_geometry`） |
| 侧别还原只在"来源空间当时恰有 2 个窗口"时执行 | ✅ decided | 多窗时"左邻"无唯一语义；此约定覆盖用户描述的场景 |
| 用户手动搬走后不再回拽 | ✅ decided | 条目在首次还原后即删除，只生效一次 |
| 池内存不得 free（`space_window_list` 的返回值） | ✅ decided | 事故根因；既有调用者都不 free |
| view 查找用只读 `space_manager_query_view` | ✅ decided | `find_view` 会为不存在的 sid 创建空 view，污染模型 |
| 版本号 7.2.0（MINOR）而非 PATCH | ✅ decided（用户已授权自行决策） | R15：新功能 → MINOR |
| 不做"全屏期间窗口被关闭后重建"的还原 | ✅ decided | 重开窗口是新窗口 id，不属于同一记忆语义 |

## Affected Files

- `src/window_manager.h`: 新增 `struct fullscreen_restore_entry` + `struct window_manager` 内记忆表字段 + 两个 API 声明（create/modify）
- `src/window_manager.c`: 实现 `window_manager_note_fullscreen_entry()` 与 `window_manager_restore_fullscreen_entries()`（create/modify）
- `src/event_loop.c`: 在 `SPACE_CHANGED` / `WINDOW_MOVED` / `WINDOW_DESTROYED` / `SLS_SPACE_DESTROYED` 四个处理器中挂调用（modify）
- `CHANGELOG.md`、`src/yabai.c`、`scripts/install.sh`: 版本 7.2.0（modify）

## Implementation Steps

1. **记忆表与捕获** — `src/window_manager.{h,c}`、`src/event_loop.c`(SPACE_CHANGED) — 复杂度低；
   交付物：进入全屏空间时打印 `[yabai] fullscreen entry: win=… src=… neighbour=… side=…`，可用日志独立验证。
2. **空间还原** — `src/window_manager.c`(restore) + `src/event_loop.c`(SPACE_CHANGED/WINDOW_MOVED) — 复杂度中；
   交付物：退出全屏后窗口回到来源空间，日志 `fullscreen restore: win=… -> space=…`；来源空间不存在时打印一次并丢弃。
3. **侧别还原** — `src/window_manager.c`（warp + 几何判定） — 复杂度中；
   交付物：2 窗左右分屏下，右侧窗口进出全屏后仍在右侧；日志 `fullscreen side restore: win=… vs …`。
4. **边界与清理** — `src/event_loop.c`（WINDOW_DESTROYED / SLS_SPACE_DESTROYED 丢弃条目）+ 上限淘汰 — 复杂度低；
   交付物：连续 20 次全屏进出后条目数不超过 8（日志一次汇总）。
5. **版本与文档** — 上述版本文件 + `CHANGELOG.md` 条目 — 复杂度低。

## Review Focus

1. 窗口在**来源空间已消失**时（用户删了那个桌面）退出全屏 → 不得报错、不得把窗口送去不存在的空间（删记忆即可）。
2. 全屏窗口**被用户手动拖到别处**后 → 不得回拽（条目已删除）。
3. **多显示器**：记忆里存绝对空间 id，跨显示器正确；来源显示器被拔出 → 视为空间消失。
4. **浮动窗口**进全屏 → 还原时不 tile（`window_manager_should_manage_window` 已在下游判断，需实测确认不炸）。
5. **应用退出**（窗口销毁）在全屏中 → 条目必须清理，不留悬挂 id。
6. 连续快速进出全屏（抖动）→ 不产生重复条目、不叠加 warp。

## Risks and Counter-examples

| 风险 | 反例/已知例外 | 缓解 |
|---|---|---|
| 还原动作与用户操作打架 | 用户在退出瞬间已把窗口搬到目标桌面 | 还原前检查窗口当前空间仍是"系统给的落点"，否则丢弃条目 |
| warp 在 >2 窗口视图里语义不唯一 | 来源空间当时有 3+ 窗口 | 仅 2 窗时执行 warp；否则只还原空间并在日志说明 |
| 记忆表泄漏 | 长时间运行、多次全屏 | 上限 8 + 四类事件清理（还原/窗口销毁/来源空间销毁/淘汰） |
| 与上游行为冲突 | 上游未实现此行为，未来可能自行加入 | 全部新增代码集中在一个文件 + 两个函数，便于摘除；CHANGELOG 标注为 workaround |

## Acceptance Criteria

- [ ] `make`（两个架构切片）零告警通过（artifact check）
- [ ] `yabai -m space --create` 在 daemon 侧仍正常（回归，runtime evidence）
- [ ] Discord（或等价窗口）在 desktop 2 → 全屏 → 退出 → `yabai -m query --windows` 显示其 `space` 仍为 desktop 2（runtime evidence，用户复现）
- [ ] 同空间两窗左右分屏、右窗进全屏 → 退出后仍在右侧（runtime evidence）
- [ ] 来源 desktop 先被销毁再退出全屏 → 无错误、窗口留在系统落点、日志只有一行 discard（runtime evidence）
- [ ] 日志可见三条：`fullscreen entry` / `fullscreen restore` / `fullscreen side restore`（perceptual review：用户读日志即可判断）

## Not Covered / Explicitly Not Doing

- 不做"全屏期间被关掉的窗口重建后还原"（新窗口新 id，语义不同）
- 不做跨显示器"拖拽到另一显示器再全屏"的位置还原（只还原空间，侧别判定默认跳过）
- 不改变 yabai 既有的 `--space`/`--warp` 语义，不给用户暴露新命令
- 不修改 SA payload，不改 SkyLight 调用，不动 `window_node` 树结构
- 不处理 macOS 27.0.1 的另一个系统侧问题（开机主屏无桌面，见 S9）
