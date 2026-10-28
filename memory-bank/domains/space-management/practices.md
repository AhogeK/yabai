# practices — 空间操作具体做法与踩坑

> **系统基线**：macOS 27.2 (26B123) · Dock 2571.1.32.402 · WindowManager 462.1.41.404
> **最后验证**：2026-10-28 · **状态**：已验证
> **来源**：三代调用样例取自实际提交代码；27.2 move/排序/destroy 真机实测

## 1. 三代创建的调用样例

```c
// G3′ (27, 2026-09-15 起): 直接调 Dock 内部创建 helper（= Mission Control "+" 同源函数）
//   x0 = cid(Dock 懒加载 getter) · w1 = flags(0) · w2 = type(0=user) ·
//   x3/x4 = Swift String(spaceUUID 的 String(NSString) 桥接，必须是新生成的 UUID) · x5 = __swiftEmptyArrayStorage
//   返回 = CGSSpaceCreate 结果（非 0 视为创建成功）
asm__call_dock_space_create(cid, 0, 0, uuid_word0, uuid_word1, swift_empty_array_storage, dock_space_create_fp, spid);
// 坑1: uuid 必须是 Swift String（String(NSString) 桥接），不是 NSString；它会被当成新空间身份
// 坑2: pids 必须是真单例——dlsym("__swiftEmptyArrayStorage") 返回 NULL，
//      要从 Dock literal pool 解码（用户空间调用点 pattern → 回溯 adrp+ldr → slot 0x3c3998）；
//      取不到就**不要调用**（NULL 会在 Dock 内崩）
// 坑3: pattern 裸地址用 blr（C 函数指针调用会生成 braaz → PAC_EXCEPTION）
```

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
- 空间创建（27）：G3 框架导出符号（dlsym）；**G3′ Dock 内部 helper 用 pattern（base 0x2b0000 / 0x2c0000）**

## 5. 排查用日志

```bash
log show --last 2m --predicate 'process == "Dock"' | grep -E "\[SPACE\]|\[WM\]|\[DPPM\]"
```

payload 侧关键行：`call space_create_entry(display_id=…)` / `synchronouslyRequestCreateManagedSpace returned (spid=…, error=…)` / `dock_spaces found at …`。

## 6. 不要做的三件事

1. 不要用 display index 跨 API 传显示器（用 UUID）
2. 不要在 DPPM 未通知的情况下认为"空间创建完成"（壁纸会错位）
3. 不要把模型回写失败当成整体失败而回滚 SLS 切换
### 27.2 move/排序已在真机验证（2026-10-28）

`CGSMoveManagedSpaceToDisplayIndex(cid, sid, displayUUID, 0)` 与 `SLSTransactionMoveManagedSpaceToDisplayAfterSpace(tx, sid, displayUUID, afterSid)` + `SLSTransactionCommit(tx, 1)` 在 Dock 2571.1.32.402 上实测有效：跨屏移动后 `query --spaces` 的 display 变化正确，排序后顺序按预期重排；`CGSSpaceDestroy` 删除空桌面后空间数正确递减。
