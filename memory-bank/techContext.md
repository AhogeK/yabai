# Technical Context - yabai

## Build Toolchain

| Component       | Configuration                                    |
|-----------------|--------------------------------------------------|
| C Standard      | C11 (`-std=c11`)                                 |
| Compiler        | Apple Clang (xcrun clang)                        |
| Deployment      | macOS 11.0+ (`-mmacosx-version-min=11.0`)        |
| Architectures   | Universal: x86_64 + arm64                        |
| Debug Build     | `-g -O0 -fvisibility=hidden`                     |
| Release Build   | `-O3 -DNDEBUG -fvisibility=hidden`               |
| Sanitizers      | asan (`-fsanitize=address,undefined`), tsan      |

## Private Frameworks

| Framework    | Purpose                              | Risk Level |
|--------------|--------------------------------------|------------|
| SkyLight     | Core window management, spaces, displays | HIGH - undocumented, changes between macOS versions |
| Carbon       | Event taps, accessibility            | MEDIUM - stable but limited |
| Cocoa        | Obj-C bridging, app lifecycle        | LOW - public API |

## SIP & Code Signing

- **SIP Disabled (Full Mode)**: scripting-addition injection into Dock.app
- **SIP Enabled (Limited Mode)**: reduced window control capabilities
- **Code Signing**: requires `yabai-cert` identity or ad-hoc (`-`)
- **sudoers**: SHA256 hash-based sudo rules for `--load-sa` command

## Key Headers

- `src/` contains private API declarations
- `.clangd` provides LSP configuration for private frameworks