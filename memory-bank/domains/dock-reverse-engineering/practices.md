# practices — 可直接照做的操作与踩坑

> **系统基线**：macOS 27.0 (26A428) · Dock 2571.0.6.402 · WindowManager 462.0.8
> **最后验证**：2026-09-15 · **状态**：已验证
> **来源**：本机跑通：lipo/otool/dyld_info 命令、cache 提取脚本、pattern 校验脚本

## 1. 取切片与反汇编

```bash
lipo -thin arm64e -output /tmp/<topic>/Dock_arm64e \
  /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
otool -l Dock_arm64e | grep -A8 "segname __TEXT"      # vmaddr 0x100000000
otool -tV Dock_arm64e > disasm.txt                    # __TEXT,__text
```

注：`otool -tV` 只覆盖 `__TEXT,__text`（止于 `__auth_stubs`/`__objc_stubs` 之前），stub 区需另想办法解码（见 §3）。

## 2. 元数据三连（定位加速器）

```bash
dyld_info -objc   Dock_arm64e > objc_dump.txt     # 类/方法名 + 方法地址（含 Swift 类）
dyld_info -fixups Dock_arm64e > fixups.txt        # __objc_selrefs → selector 字符串
nm -u Dock_arm64e | sed 's/^_//' | xcrun swift-demangle   # 导入符号（Swift 语义）
```

## 3. 语义画像（判定"某个全局是什么对象"）

1. 从 `fixups.txt` 建 `selref_addr → selector`；
2. 扫 `__TEXT,__objc_stubs`（27.0 为 `0x1002e8200–0x1002fb360`），解 `adrp+ldr` 得 `stub → selector`；
3. 对 `__text` 做**寄存器级抽象解释**（跟踪 `adrp/add/ldr/mov/bl`，bl 视为 clobber x0–x18），记录每次 `bl <stub>` 时 `x0` 是哪个全局；
4. 统计"全局 × 方法名"矩阵 → 语义指纹。

**踩坑**：`objc_retain` 之类会清掉 x0 追踪，需要"retain 透传"（返回值 = 入参全局）；`mov` 复制要在跟踪表里同步。

## 4. dyld shared cache 提取（框架只在 cache 里时）

```bash
python3 dyld_cache_extract.py WindowManager.framework /tmp/WindowManager_extracted
otool -tV /tmp/WindowManager_extracted | grep -A 20 "<VA>"
dyld_info -exports <framework path> | awk '{print $2}' | xcrun swift-demangle
```

脚本全文见 `docs/reverse-engineering-macos27-space-create.md` 附录 A（cache 主文件 + `.NN` 子缓存映射 → 重建 Mach-O，剔除 `__LINKEDIT`）。

## 5. pattern 校验脚本（改 pattern 后必跑）

见 `docs/reverse-engineering-macos27-space-create.md` 附录 B：从 `arm64_payload.m` 提取某主版本分支的 offset/pattern，复刻 `hex_find_seq`（窗口 `0x1286a0`）并打印命中地址 + adrp 解码目标。

## 6. 内联汇编宏（Swift 调用）

- 操作数名**不得与宏参数同名**：预处理器会把操作数段里的参数替换掉，而字符串 `%[name]` 不替换 → clang 报 `unknown symbolic operand name`
- 单块 `asm volatile` + `blr` + 完整 clobber（`x0..x17`、`x19..`、`x20`/`x21`、`x30`、`memory`）
- 调用前清零错误寄存器（如 Swift throws 的 `x21`），调用后读取

## 7. 构建坑

- `make BUILD_PATH=<tmp>` 前需 `mkdir -p <tmp>/yabai_bin`（`xxd` 输出目录不自动创建）
- `xcrun clang` 若报 Xcode license 未接受：`DEVELOPER_DIR=/Library/Developer/CommandLineTools make`
- SA 侧改动需 arm64e 可编译；主程序需 x86_64 + arm64 双架构通过
