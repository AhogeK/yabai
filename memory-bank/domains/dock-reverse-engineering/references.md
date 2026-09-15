# references — 偏移 / pattern / 符号 / 单例事实表

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：已验证
> **来源**：27.0 偏移在 binary 上静态唯一命中（`docs/…macos27…` 附录 B 脚本）+ 用户实测空间功能恢复

> 不含判断，只查表。**pattern 字符串本体以 `src/osax/arm64_payload.m` 为准**，本表记录"它命中了哪里、解出什么"。

## 版本矩阵（Dock 侧）

| 项目 | macOS 26.0 (`0x1f07d8`) | macOS 26.6 (25G72 / Dock 2427.6) | **macOS 27.0 (26A428 / Dock 2571.0.6.402)** |
|---|---|---|---|
| `dock_spaces` base / 命中 | 0x30000 / — | 0x30000 / — | **0x30000 / 0x30a98 → 全局 0x100409bb0** |
| `dppm` base / 命中 | 0x70000 / — | 0x70000 / — | **0x40000 / 0x509fc → 全局 0x100409c50** |
| `add_space` base | 0x250000 | 0x250000 | **0（无 Dock 内实现）** |
| `remove_space` base / 命中 | 0x1e0000 | 0x1e0000 | **0x180000 / 0x18b9a0** |
| `move_space` base / 命中 | 0x1c0000 | 0x1c0000 | **0x180000 / 0x18c554** |
| `fix_animation` base / 命中 | 0x250000 | 0x250000 | **0x220000 / 0x227508** |
| `set_front_window` base / 命中 | 0x10000 | 0x10000 | **0x10000 / 0x192bc**（pattern 首字节改通配） |
| `space_create_entry` | 0x1f07d8 | **0x1f07d4**（pacibsp 前移 4 字节） | **不存在** → 走 `WindowManager.framework` |
| `dock_space_create` helper | — | — | **0x2b0000 / 0x2bb62c**（Swift helper，21 处调用点；用户空间调用点 0x1744cc = flags0/type0） |
| `dock_cid_getter` | — | — | **0x2c0000 / 0x2c2aa8**（swift_once 守卫的 cid 缓存，全局 0x41e174） |
| `pids_array_site`（空 pid 数组调用点） | — | — | **0x170000 / 0x1744bc** → 回溯 adrp+ldr 得 literal slot **0x3c3998**（`__swiftEmptyArrayStorage`，dlsym 取不到） |
| Spaces 单例全局 | 0x488028 | 0x488028 | 0x100409bb0 |
| DPPM 单例全局 | 0x4880d0 | 0x4880d0 | 0x100409c50 |

## 单例全局语义画像（macOS 27.0）

| 全局地址 | 接收方法（节选） | 判定 |
|---|---|---|
| `0x100409bb0` | `currentSpaceForDisplay:` `allUserSpaces` `currentSpaces` `switchToNextSpace:` `firstUserSpaceForDisplay:` | **Spaces 单例**（= `dock_spaces`） |
| `0x100409c50` | `addSpace:forDisplayUUID:` `removeSpace:` `moveSpace:toDisplay:displayUUID:` `addFullscreenSpace:forDisplayUUID:` | **DPPM**（WallpaperAgentDesktopPictureManager） |
| `0x100409c28` | `dockConnection` `darkDock` `dragWindow` `setMainMillis:` | Dock 设置对象（yabai 不用） |
| `0x100409ba0` | `_handleEvent:location:flags:` `_getCornerActions:` | 热区控制器（yabai 不用） |

## 稳定 pattern（跨版本未变）

```
dock_spaces (26/27) : ?8 ?? ?? ?? 08 ?? ?? 91 00 01 40 F9 E2 03 13 AA ?? ?? ?? 94 ?? ?? ?? ?? 08
dppm        (26/27) : ?? ?? 00 ?? 08 ?? ?? 91 00 01 40 F9 E2 03 16 AA E3 03 19 AA ?? ?? ?? 94
fix_animation (26/27): 00 10 6A 1E A8 ?? ?? D1 ?? 01 ?? F8
set_front_window (27): ?? ?? ?? 34 7F 23 03 D5 FF C3 01 D1 F6 57 04 A9 F4 4F 05 A9 FD 7B 06 A9 FD 83 01 91dock_space_create (27): 7F 23 03 D5 E6 03 1E AA ?? ?? ?? ?? FE 03 06 AA FD 7B 06 A9 FD 83 01 91 F6 03 05 AA F8 03 04 AA F9 03 03 AA F4 03 02 AA F3 03 01 AA F5 03 00 AA
dock_cid_getter   (27): 7F 23 03 D5 FF 03 01 D1 F4 4F 02 A9 FD 7B 03 A9 FD C3 00 91 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? F3 0A 00 90 73 D2 05 91pids_array_site   (27): 01 00 80 52 02 00 80 52 E3 03 15 AA E4 03 16 AA ?? ?? ?? 94
```

## WindowManager.framework（macOS 27，导出符号，dlsym 名称去掉前导下划线）

| 符号 | 用途 | 导出偏移（仅参考，随 cache 构建变化） |
|---|---|---|
| `$s13WindowManagerAACMa` | type metadata accessor | — |
| `$s13WindowManagerAAC6sharedABvgZ` | `WindowManager.shared` getter | 0x586B4 |
| `$s13WindowManagerAAC38synchronouslyRequestCreateManagedSpace11displayUUIDs6UInt64VSSSg_tKF` | 创建空间 | 0x58EC4 |
| `$s13WindowManagerAAC32synchronouslyRequestDestroySpaceyys6UInt64VKF` | 销毁空间 | 0x58EE8 |
| `$s13WindowManagerAAC29provideVisibilityHintForSpace03forG0ys6UInt64V_tKF` | 可见性提示 | 0x58F0C |
| `$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ` | `String(NSString)`（Foundation 导出） | — |
| `swift_errorRelease` | 释放 `swift_error*`（C 符号） | — |

## 相关路径

| 用途 | 路径 |
|---|---|
| Dock 二进制 | `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock` |
| 框架（27，仅 cache） | `/System/Library/PrivateFrameworks/WindowManager.framework/Versions/A/WindowManager` |
| dyld shared cache | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e[.NN]` |
| 完整逆向记录 | `docs/reverse-engineering-*.md`、`docs/macos26/` |
| 当前系统版本速查 | `memory-bank/techContext.md` |
