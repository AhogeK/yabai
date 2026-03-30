FRAMEWORK_PATH = -F/System/Library/PrivateFrameworks
FRAMEWORK      = -framework Carbon -framework Cocoa -framework CoreServices -framework CoreVideo -framework SkyLight
CLI_FLAGS      =
BUILD_FLAGS    = -std=c11 -Wall -Wextra -g -O0 -fvisibility=hidden -mmacosx-version-min=11.0 -fno-objc-arc -arch x86_64 -arch arm64 -sectcreate __TEXT __info_plist $(INFO_PLIST)
BUILD_PATH     = $(HOME)/.local/bin
DOC_PATH       = ./doc
SCRIPT_PATH    = ./scripts
ASSET_PATH     = ./assets
SMP_PATH       = ./examples
ARCH_PATH      = ./archive
OSAX_SRC       = $(BUILD_PATH)/yabai_bin/payload_bin.c $(BUILD_PATH)/yabai_bin/loader_bin.c
YABAI_SRC      = ./src/manifest.m $(OSAX_SRC)
OSAX_PATH      = ./src/osax
INFO_PLIST     = $(ASSET_PATH)/Info.plist
BINS           = $(BUILD_PATH)/yabai

.PHONY: all asan tsan install man icon archive publish sign clean-build clean

all: clean-build $(BINS)

asan: BUILD_FLAGS=-std=c11 -Wall -Wextra -g -O0 -fvisibility=hidden -fsanitize=address,undefined -mmacosx-version-min=11.0 -fno-objc-arc -arch x86_64 -arch arm64 -sectcreate __TEXT __info_plist $(INFO_PLIST)
asan: clean-build $(BINS)

tsan: BUILD_FLAGS=-std=c11 -Wall -Wextra -g -O0 -fvisibility=hidden -fsanitize=thread,undefined -mmacosx-version-min=11.0 -fno-objc-arc -arch x86_64 -arch arm64 -sectcreate __TEXT __info_plist $(INFO_PLIST)
tsan: clean-build $(BINS)

install: BUILD_FLAGS=-std=c11 -Wall -Wextra -DNDEBUG -O3 -fvisibility=hidden -mmacosx-version-min=11.0 -fno-objc-arc -arch x86_64 -arch arm64 -sectcreate __TEXT __info_plist $(INFO_PLIST)
install: clean-build $(BINS)

$(OSAX_SRC): $(OSAX_PATH)/loader.m $(OSAX_PATH)/payload.m
	xcrun clang $(OSAX_PATH)/payload.m -shared -fPIC -O3 -mmacosx-version-min=11.0 -arch x86_64 -arch arm64e -o $(OSAX_PATH)/payload $(FRAMEWORK_PATH) -framework SkyLight -framework Foundation -framework Carbon
	xcrun clang $(OSAX_PATH)/loader.m -O3 -mmacosx-version-min=11.0 -arch x86_64 -arch arm64e -o $(OSAX_PATH)/loader -framework Cocoa
	xxd -i -a $(OSAX_PATH)/payload $(BUILD_PATH)/yabai_bin/payload_bin.c
	xxd -i -a $(OSAX_PATH)/loader $(BUILD_PATH)/yabai_bin/loader_bin.c
	rm -f $(OSAX_PATH)/payload
	rm -f $(OSAX_PATH)/loader

man:
	asciidoctor -b manpage $(DOC_PATH)/yabai.asciidoc -o $(DOC_PATH)/yabai.1

icon:
	python3 $(SCRIPT_PATH)/seticon.py $(ASSET_PATH)/icon/2x/icon-512px@2x.png $(BUILD_PATH)/yabai

publish:
	sed -i '' "60s/^VERSION=.*/VERSION=\"$(shell $(BUILD_PATH)/yabai --version | cut -d "v" -f 2)\"/" $(SCRIPT_PATH)/install.sh
	sed -i '' "61s/^EXPECTED_HASH=.*/EXPECTED_HASH=\"$(shell shasum -a 256 $(BUILD_PATH)/$(shell $(BUILD_PATH)/yabai --version).tar.gz | cut -d " " -f 1)\"/" $(SCRIPT_PATH)/install.sh

archive: man install sign icon
	rm -rf $(ARCH_PATH)
	mkdir -p $(ARCH_PATH)
	cp -r $(BUILD_PATH) $(ARCH_PATH)/
	cp -r $(DOC_PATH) $(ARCH_PATH)/
	cp -r $(SMP_PATH) $(ARCH_PATH)/
	tar -cvzf $(BUILD_PATH)/$(shell $(BUILD_PATH)/yabai --version).tar.gz $(ARCH_PATH)
	rm -rf $(ARCH_PATH)

sign:
	codesign -fs "yabai-cert" $(BUILD_PATH)/yabai

clean-build:
	rm -rf $(BINS)

clean: clean-build
	rm -f $(OSAX_SRC)

$(BUILD_PATH)/yabai: $(YABAI_SRC)
	mkdir -p $(BUILD_PATH)/yabai_bin
	xcrun clang $^ $(BUILD_FLAGS) $(CLI_FLAGS) $(FRAMEWORK_PATH) $(FRAMEWORK) -o $@

# --- 路径定义 ---
USER_NAME = $(shell whoami)

.PHONY: deploy
deploy:
	@echo "🧹 [1/6] 停止并卸载旧服务..."
	-$(BINS) --stop-service 2>/dev/null || true
	-sudo $(BINS) --uninstall-sa 2>/dev/null || true
	-$(BINS) --uninstall-service 2>/dev/null || true

	@echo "🏗️  [2/6] 清理并重新编译..."
	@$(MAKE) clean
	@$(MAKE) install

	@echo "📚 [3/6] 生成手册页..."
	@$(MAKE) man

	@echo "🔐 [4/6] 签名二进制文件..."
	@codesign -fs - $(BINS)

	@echo "🔑 [5/6] 更新 sudoers 权限..."
	@NEW_HASH=$$(shasum -a 256 $(BINS) | cut -d " " -f 1); \
	SUDO_LINE="$(USER_NAME) ALL=(root) NOPASSWD: sha256:$$NEW_HASH $(BINS) --load-sa"; \
	echo "$$SUDO_LINE" | sudo tee /private/etc/sudoers.d/yabai > /dev/null

	@echo ""
	@echo "-------------------------------------------------------"
	@echo "⚠️  请在弹出的系统设置中添加 Accessibility 权限："
	@echo "1. 点击左侧 [隐私与安全性] → [辅助功能]"
	@echo "2. 找到列表中的 yabai（如果已存在，请先关闭再删除）"
	@echo "3. 用 [+] 号添加：~/.local/bin/yabai"
	@echo "4. 确保开关为 [开启] 状态"
	@echo "5. 关闭系统设置窗口"
	@echo "6. 回到终端，按回车键继续..."
	@echo "-------------------------------------------------------"
	@echo ""
	@open -a "System Settings"
	@-sh -c "read -p "按回车继续..." _"

	@echo "🚀 [6/6] 加载 SA 并启动服务..."
	# ---- 避免些特殊情况，再执行一遍 -----
	$(BINS) --stop-service 2>/dev/null || true
	sudo $(BINS) --uninstall-sa 2>/dev/null || true
	$(BINS) --uninstall-service 2>/dev/null || true
	# ----------------------------------
	sudo $(BINS) --load-sa
	$(BINS) --install-service	
	$(BINS) --start-service
	@echo ""
	@echo "-------------------------------------------------------"
	@pgrep -x yabai > /dev/null && echo "✅ 部署完美达成！" || echo "❌ 启动失败，请检查 /tmp/yabai_$(USER_NAME).err.log"
