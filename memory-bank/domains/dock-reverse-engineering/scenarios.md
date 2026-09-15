# scenarios — 触发场景 → 判断 → 动作

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：方法论
> **来源**：S1 七步流程已用于 26.6 与 27.0 两次适配

## S1. 系统升级后 space/窗口功能"再次失效"

**判断顺序（不要跳步）**：

1. **版本门**：`src/osax/payload.m` 的 `verify_os_version()` 是否覆盖新主版本？未覆盖 → `init_instances()` 直接 return，**所有** SA 能力为 0（症状最像"全坏"）。x86_64 分支只在确有 Intel 版本时加。
2. **二进制是否真的变了**：`defaults read /System/Library/CoreServices/Dock.app/Contents/Info.plist CFBundleVersion`；版本号不变 → 不需要动 pattern。
3. **Dock 版本对照**：记录 Dock 版本 + macOS build 到 `techContext.md` 与 `references.md`。
4. **逐条重跑 pattern**：用 `practices.md` 的校验脚本跑全部 `get_*_pattern()`，输出命中地址与窗口内判定。
5. **核对基线**：0 命中且函数确实存在 → 降低 `base`（函数下移）；命中但解出的全局不对 → 取窗口内第一个匹配的语义是否被抢走。
6. **确认能力代际**：目标能力是否已被 Apple 搬走（如 27 的空间创建 → `WindowManager.framework`），见 S3。
7. **编译 + 动态验证**：双架构 `make`；SA 侧日志前缀 `[yabai-sa]`。

## S2. pattern 命中 0 次（函数仍应存在）

- 先看 pattern 的**首字节**：若是条件分支/短跳转的立即数位 → 改为 `?? ?? ?? 3X` 通配首字，再验证唯一性
- 栈帧大小变化：`sub sp, sp, #0xN` 的 `FF ?? ?? D1` 中相应字节通配
- 仍 0 命中 → 函数被重写/内联：改用**语义锚点**（selector 调用点、字符串引用链）重新定位

## S3. 目标入口从 Dock 消失（架构搬迁）

症状：全 binary 搜 pattern/selector 都找不到，但功能仍在（用户手点可用）。

**判断**：`otool -L Dock` 看新依赖的私有框架；`nm -u Dock | swift-demangle` 看是否改用框架 API。

**动作**：转向框架级 API（27 的 `WindowManager.WindowManager.synchronouslyRequestCreateManagedSpace(displayUUID:)`），用 `dlsym` 解析 mangled Swift 符号并复刻 Swift 调用约定，比继续找 Dock 内偏移更稳（不再随 Dock 重编译漂移）。

框架只在 dyld shared cache → 提取流程见 `practices.md`。

## S4. 需要判断"某个全局变量到底是什么对象"

按 `principles.md` 的三要素做语义画像；**不要**靠地址邻近关系猜测（`0x100409ba0/bb0/c28/c50` 四个全局紧邻但分属热区控制器/Spaces/设置/DPPM）。

## S5. 指纹类定位（控制流指纹）突然失效

先确认是**指纹函数被重写**还是**区域扫描范围不足**。指纹失效不等于能力失效：`payload.m` 中指纹路径失败后必须能退回 pattern 路径（26 的 DPPM 即如此），并避免在已解析成功时重复跑指纹刷 ERROR 日志。

## S6. Dock 崩溃 / 反复重启（SA 改动后的头号怀疑对象）

**现场顺序**（崩溃会丢掉 NSLog 缓冲，日志里可能**什么都看不到**，不要因此误判"没执行"）：

1. `ls -lt ~/Library/Logs/DiagnosticReports/ | grep Dock` → 取最新 `Dock-*.ips`
2. 读关键字段：`exception.type` / `exception.subtype` / `termination.namespace`
3. 判断：
   - `termination.namespace == PAC_EXCEPTION`（或 subtype 出现 "possible pointer authentication failure"）→ **间接调用未认证**：dlsym/编译器取址的指针被裸 `blr` 调用。修法与判定口诀见 `scripting-addition/practices.md` §4.1
   - `EXC_BAD_ACCESS` at 0x0/0x1 → 空指针/参数约定错误（返回 `scenarios.md` S1）
4. 定位到指令：崩溃线程 `frame[1]` 的 `symbol + offset` = 我们代码中的**返回地址**；`nm -arch arm64e <payload> | grep <symbol>` 得符号起始偏移，`offset - symbol_off` 即崩溃点，反汇编该处即可看到具体调用指令
5. 复现：Dock 崩溃后会自动重启，SA 每次加载都会重跑 `init_instances()`，因此"日志里 Dock 反复出现 `loaded payload..`"本身就是崩溃循环的证据

## S7. 调用 pattern 定位到的 Dock 函数时进程崩溃（PAC_EXCEPTION）

**判断**：崩溃报告 `termination.namespace = PAC_EXCEPTION`，faulting frame 落在 Dock 的裸地址上。

**动作**：
1. **先判断指针签名状态**（`payload.m` 中 `ptrauth_sign_unauthenticated` 过的：addSpace / removeSpace / moveSpace / setFrontWindow）：
   - 已签名 → 必须用**认证分支**（C 调用即可，clang 生成 `braaz`）；用裸 `blr` 必崩（27 实测：`space --destroy` 就是这样被弄崩的）
   - 未签名（pattern 扫出的裸地址）→ 必须用**裸 `blr`**；C 调用会认证失败
2. **dlsym() 指针**已签名 → 用 `blraaz`。
3. 若被调函数是 Swift 函数且参数含 `Array/String`：`String` 走 `String(NSString)` 桥接；**空数组单例 dlsym 取不到**，要从调用点的 `adrp+ldr` 解码 literal pool（27.0：slot 0x3c3998）；**取不到就不要调用**。
4. image 相对 offset 必须加在 `_dyld_get_image_header(0)` 指向的运行时地址上（不是它减去 0x100000000）。
