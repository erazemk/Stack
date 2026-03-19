APP_NAME := Stack
APP_BUNDLE := $(APP_NAME).app
PACKAGE_DIR := src
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_BUNDLE)
INSTALL_DIR := $(HOME)/Applications
BUNDLE_DIR := $(PACKAGE_DIR)/Bundle
LOCALIZATION_DIR := $(PACKAGE_DIR)/Sources/Stack/en.lproj

install: build
	@was_running=0; \
	if pgrep -x "$(APP_NAME)" >/dev/null; then \
		was_running=1; killall "$(APP_NAME)"; \
		while pgrep -x "$(APP_NAME)" >/dev/null; do sleep 0.1; done; \
	fi; \
	[ ! -d "$(INSTALL_DIR)/$(APP_BUNDLE)" ] || rm -rf "$(INSTALL_DIR)/$(APP_BUNDLE)"; \
	mkdir -p "$(INSTALL_DIR)"; \
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)/"; \
	[ "$$was_running" -ne 1 ] || open "$(INSTALL_DIR)/$(APP_BUNDLE)"
.PHONY: install

build:
	swift build --package-path $(PACKAGE_DIR) --scratch-path $(BUILD_DIR) -c release
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources $(APP_DIR)/Contents/Resources/en.lproj
	cp $(BUILD_DIR)/release/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp $(BUNDLE_DIR)/Info.plist $(APP_DIR)/Contents/Info.plist
	cp $(BUNDLE_DIR)/Resources/AppIcon.icns $(APP_DIR)/Contents/Resources/AppIcon.icns
	cp $(LOCALIZATION_DIR)/Localizable.strings $(APP_DIR)/Contents/Resources/en.lproj/Localizable.strings
.PHONY: build
