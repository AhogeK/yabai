# practices — 空间操作具体做法与踩坑

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：已验证
> **来源**：三代调用样例取自实际提交代码；沙箱结论来自 26.x 实测

## 1. 三代创建的调用样例

```c
// G1 (≤25): x0 = new_space, x20 = display_space
asm__call_add_space(new_space, display_space, add_space_fp);

// G2 (26.x): x0 = display_id(int32), x20 = Spaces 单例；需主线程
dispatch_sync(dispatch_get_main_queue(), ^{
    asm__call_space_create_tahoe((uint32_t)display_id, retained_spaces, space_create_entry_fp);
});

// G3 (27+): x20 = WindowManager.shared, x0/x1 = Swift String(UUID), x21 = error
void *wm = wm_shared();                                   // 静态 getter（x20 = metatype）
swift_string_t uuid = bridge_nsstring_to_swift(display_uuid);
asm__call_wm_create_space(uuid.w0, uuid.w1, wm, wm_create_space_fp, spid, err);
```

## 2. display UUID ↔ CGDirectDisplayID

```c
CFStringRef uuid = SLSCopyManagedDisplayForSpace(SLSMainConnectionID(), space_id);   // 主键
CGDirectDisplayID did = display_id_for_uuid(uuid);   // 逐个 active display 比对 CGDisplayCreateUUIDFromDisplayID
```

**踩坑**：`CGDisplayIOServicePort()` / IOKit 在 Dock 沙箱内返回 `MACH_PORT_NULL`（静默失败），一律走 CoreGraphics。

## 3. 切换空间的四连调用（顺序）

```c
SLSShowSpaces(cid, dest);  SLSHideSpaces(cid, source);
SLSManagedDisplaySetCurrentSpace(cid, display_uuid, dest_sid);
set_ivar_value(display_space, "_currentSpace", dest_space);   // 模型回写，失败不致命
```

## 4. 定位空间相关入口的锚点

- `dock_spaces`：`doBindingCommand:display` 特征 pattern（26/27 通用）
- DPPM：`DPRemoteConnection::_handleEvent:` pattern（27）或 setter 控制流指纹（26）
- 空间创建（26）：从 DPPM `addSpace:forDisplayUUID:` 调用栈反推
- 空间创建（27）：框架导出符号（不再依赖 Dock 偏移）

## 5. 排查用日志

```bash
log show --last 2m --predicate 'process == "Dock"' | grep -E "\[SPACE\]|\[WM\]|\[DPPM\]"
```

payload 侧关键行：`call space_create_entry(display_id=…)` / `synchronouslyRequestCreateManagedSpace returned (spid=…, error=…)` / `dock_spaces found at …`。

## 6. 不要做的三件事

1. 不要用 display index 跨 API 传显示器（用 UUID）
2. 不要在 DPPM 未通知的情况下认为"空间创建完成"（壁纸会错位）
3. 不要把模型回写失败当成整体失败而回滚 SLS 切换
