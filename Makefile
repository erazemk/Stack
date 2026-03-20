APP_NAME := Stack
BUNDLE_ID := com.erazemk.Stack
APP_BUNDLE := $(APP_NAME).app
PACKAGE_DIR := src
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_BUNDLE)
INSTALL_DIR := $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_BUNDLE)
BUNDLE_DIR := $(PACKAGE_DIR)/Bundle
LOCALIZATION_DIR := $(PACKAGE_DIR)/Sources/Stack/en.lproj

install: build
	@set -eu; \
	was_running=0; \
	if pgrep -x "$(APP_NAME)" >/dev/null; then \
		was_running=1; \
		echo "Stopping $(APP_NAME)..."; \
		osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true; \
		for _ in $$(seq 1 50); do \
			pgrep -x "$(APP_NAME)" >/dev/null || break; \
			sleep 0.1; \
		done; \
		if pgrep -x "$(APP_NAME)" >/dev/null; then \
			killall "$(APP_NAME)" >/dev/null 2>&1 || true; \
			while pgrep -x "$(APP_NAME)" >/dev/null; do sleep 0.1; done; \
		fi; \
	fi; \
	mkdir -p "$(INSTALL_DIR)"; \
	if [ -d "$(INSTALLED_APP)" ]; then \
		echo "Replacing $(INSTALLED_APP)..."; \
		rm -rf "$(INSTALLED_APP)"; \
	fi; \
	echo "Installing $(APP_BUNDLE) to $(INSTALL_DIR)..."; \
	ditto "$(APP_DIR)" "$(INSTALLED_APP)"; \
	if [ "$$was_running" -eq 1 ]; then \
		echo "Restarting $(APP_NAME)..."; \
		open "$(INSTALLED_APP)"; \
	else \
		echo "Installed $(APP_NAME) to $(INSTALLED_APP)"; \
	fi
.PHONY: install

build:
	swift build --package-path $(PACKAGE_DIR) --scratch-path $(BUILD_DIR) -c release
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources $(APP_DIR)/Contents/Resources/en.lproj
	cp $(BUILD_DIR)/release/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp $(BUNDLE_DIR)/Info.plist $(APP_DIR)/Contents/Info.plist
	cp $(BUNDLE_DIR)/Resources/AppIcon.icns $(APP_DIR)/Contents/Resources/AppIcon.icns
	cp $(LOCALIZATION_DIR)/Localizable.strings $(APP_DIR)/Contents/Resources/en.lproj/Localizable.strings
.PHONY: build
