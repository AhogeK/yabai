# Active Context - yabai

## ✅ 7.2.6 空间身份修复 —— 主屏失背景已闭环（2026-10-23）

- **现象**：开机后主屏无壁纸、Mission Control 只见 1 个桌面（无桌面方块）；建/删桌面后反复复发；窗口上下窜动
- **取证**：关机前 `managed space order: [50,3258,58,81,90,84,72,2380]`（健康）→ 开机 `[6,6,6,6,6,6,6]`；yabai 比损坏日志晚 4 秒启动（非开机写入者）
- **决定性对照**：系统 Mission Control “+” 建的空间 id 33 → `uuid=442D311F…`（唯一）；yabai 建的空间 id 26 → `uuid=37D8832A…`（显示器 UUID）
- **根因**：macOS 27 `do_space_create` 把显示器 UUID 当新空间身份传给 Dock helper；helper 原样写入 `CGSSpaceCreate` 的 `@{type,uuid,pid}` → 同显示器所有 yabai 空间共享一个身份 → `com.apple.spaces` 按身份持久化 → 开机恢复把重复身份全部映射到同一 id → 桌面层取不到壁纸
- **旧结论作废**：S9 的“纯系统侧 / `space --create` 可修复”是错的——create 本身在污染身份，越修越脏（更正见 `domains/space-management/scenarios.md` S9）
- **修复**（7.2.6 / OSAX 2.1.34，编译 0 警告）：create 改传 `CFUUIDCreate` + `CFUUIDCreateString` 生成的新 UUID；创建后用 `SLSCopyManagedDisplayForSpace` 校验落点（不符打 WARNING）；Swift 桥不可用则中止
- **实测**：`space --create` 返回 id 40、`uuid=ACE42D27…`（唯一）；清理 `com.apple.spaces` + 注销/重启后三台显示器 order 为 `[1]` / `[6]` / `[7]`，`query --spaces` count=3 unique=3，壁纸恢复、窜动消失
- **处置要点**：删除域后 plist 变 42 字节空壳（`{}`）属正常；必须在注销/重启**之前**确认域为空，否则 WindowManager 会按旧模型重建
- 计划：`docs/plans/2026-10-23-space-create-uuid-identity.md`（completed）

## 当前工作焦点

无进行中任务。7.2.6 已部署并验证；后续按日常使用观察是否复发。

## 已知设计限制（不处理）

| 问题 | 原因 |
|------|------|
| 跨 space 失焦窗口透明度不恢复 | 原版设计，非本次引入 |
| 重试 10 次魔法数字（1 秒覆盖） | Apple 未暴露相关 API，无完美解法 |

## 📚 历史锚点

- 7.2.0–7.2.5 全屏还原与视图跟随：`progress.md` Phase 40（含一次 `space_window_list()` 池内存误 free 的崩溃事故与教训）
- macOS 27 空间创建三代实现的完整历程：`progress.md` Phase 39 + `domains/space-management/principles.md`
- macOS 26 世代细节：`archive/activeContext-2026-10.md`，领域结论见 `domains/`
