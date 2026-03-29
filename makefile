FRAMEWORK_PATH = -F/System/Library/PrivateFrameworks
FRAMEWORK      = -framework Carbon -framework Cocoa -framework CoreServices -framework CoreVideo -framework SkyLight
CLI_FLAGS      =
BUILD_FLAGS    = -std=c11 -Wall -Wextra -g -O0 -fvisibility=hidden -mmacosx-version-min=11.0 -fno-objc-arc -arch x86_64 -arch arm64 -sectcreate __TEXT __info_plist $(INFO_PLIST)
BUILD_PATH     = ./bin
DOC_PATH       = ./doc
SCRIPT_PATH    = ./scripts
ASSET_PATH     = ./assets
SMP_PATH       = ./examples
ARCH_PATH      = ./archive
OSAX_SRC       = ./src/osax/payload_bin.c ./src/osax/loader_bin.c
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
	xxd -i -a $(OSAX_PATH)/payload $(OSAX_PATH)/payload_bin.c
	xxd -i -a $(OSAX_PATH)/loader $(OSAX_PATH)/loader_bin.c
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
	rm -rf $(BUILD_PATH)

clean: clean-build
	rm -f $(OSAX_SRC)

$(BUILD_PATH)/yabai: $(YABAI_SRC)
	mkdir -p $(BUILD_PATH)
	xcrun clang $^ $(BUILD_FLAGS) $(CLI_FLAGS) $(FRAMEWORK_PATH) $(FRAMEWORK) -o $@

# --- 路径定义 ---
YABAI_BIN_ABS = $(shell pwd)/bin/yabai
USER_NAME = $(shell whoami)

.PHONY: deploy
deploy:
	@echo "🧹 [1/5] 深度清理环境..."
	-@$(YABAI_BIN_ABS) --stop-service 2>/dev/null || true
	-@killall yabai 2>/dev/null || true
	@rm -f /tmp/yabai_$(USER_NAME).lock
	@rm -f /tmp/yabai_$(USER_NAME).socket

	@echo "🏗️  [2/5] 重新编译并签名..."
	@$(MAKE) install
	@codesign -fs - $(YABAI_BIN_ABS)

	@echo "🔑 [3/5] 更新 sudoers 权限..."
	@NEW_HASH=$$(shasum -a 256 $(YABAI_BIN_ABS) | cut -d " " -f 1); \
	SUDO_LINE="$(USER_NAME) ALL=(root) NOPASSWD: sha256:$$NEW_HASH $(YABAI_BIN_ABS) --load-sa"; \
	echo "$$SUDO_LINE" | sudo tee /private/etc/sudoers.d/yabai > /dev/null

	@echo "🚀 [4/5] 尝试点火启动..."
	@$(YABAI_BIN_ABS) --start-service
	@sleep 1 # 给系统一点反应时间

	@echo "🔍 [5/5] 权限自检..."
	@if ! pgrep -x yabai > /dev/null; then \
		echo "⚠️  检测到权限拦截！正在为您唤起系统设置..."; \
		open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"; \
		echo "-------------------------------------------------------"; \
		echo "👉 请在弹出的窗口中执行以下操作："; \
		echo "1. 找到列表中的 yabai（如果已存在，请先用 [-] 号删掉再手动添加本项目 bin/yabai）"; \
		echo "2. 确保勾选开关为 [开启] 状态"; \
		echo "3. 完成后回到终端，按任意键重试启动..."; \
		echo "-------------------------------------------------------"; \
		read; \
		$(YABAI_BIN_ABS) --start-service; \
	fi
	@pgrep -x yabai && echo "✅ 部署完美达成！" || echo "❌ 仍然失败，请检查 /tmp/yabai_$(USER_NAME).err.log"