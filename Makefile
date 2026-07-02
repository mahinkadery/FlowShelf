APP        := FlowShelf
BUNDLE     := $(APP).app
CONFIG     := release
BIN        := .build/$(APP)-universal
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
INSTALL_DIR := /Applications

# Code-signing identity. A STABLE identity is critical: ad-hoc ("-") changes the
# signature every build, so macOS RESETS Accessibility/Screen-Recording grants on
# every update (TCC keys on the signature's designated requirement). We default to
# a self-signed "FlowShelf Self-Signed" cert: it's a stable identity (grants
# persist across updates) AND runs on any Mac (unlike an Apple Development cert).
# Create it once with `make cert-help`. Falls back to ad-hoc if it's missing.
CODESIGN_ID ?= FlowShelf Self-Signed

.PHONY: all build bundle embed-sparkle icon sign run clean install developer-id-bundle dist release notary-setup dmg set-version cert-help

all: bundle

# Universal build: compile each arch (full Xcode's multi-arch needs xcbuild, which
# Command Line Tools lacks), then lipo the slices into one fat binary.
build:
	swift build -c $(CONFIG) --arch arm64
	swift build -c $(CONFIG) --arch x86_64
	@lipo -create \
		.build/arm64-apple-macosx/$(CONFIG)/$(APP) \
		.build/x86_64-apple-macosx/$(CONFIG)/$(APP) \
		-output $(BIN)
	@echo "Universal binary: $$(lipo -archs $(BIN))"

bundle: build icon
	@rm -rf $(BUNDLE)
	@mkdir -p $(MACOS_DIR) $(CONTENTS)/Resources
	@cp $(BIN) $(MACOS_DIR)/$(APP)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns; fi
	@if [ -f Resources/buymeacoffee.png ]; then cp Resources/buymeacoffee.png $(CONTENTS)/Resources/buymeacoffee.png; fi
	@if [ -f Resources/MenuBarIcon.png ]; then cp Resources/MenuBarIcon.png $(CONTENTS)/Resources/MenuBarIcon.png; fi
	@SPK=$$(find .build/artifacts -name Sparkle.framework -type d -path '*macos*' | head -1); \
	if [ -n "$$SPK" ]; then \
		mkdir -p $(CONTENTS)/Frameworks; \
		ditto "$$SPK" $(CONTENTS)/Frameworks/Sparkle.framework; \
		install_name_tool -add_rpath @executable_path/../Frameworks $(MACOS_DIR)/$(APP) 2>/dev/null || true; \
		echo "Embedded Sparkle.framework"; \
	else echo "Sparkle.framework not found (run swift build first)"; exit 1; fi
	@codesign --force --deep --sign "$(CODESIGN_ID)" \
		--entitlements Resources/FlowShelf.entitlements $(BUNDLE) 2>/dev/null \
		&& echo "Signed $(BUNDLE) (identity: $(CODESIGN_ID))" \
		|| (codesign --force --deep --sign - $(BUNDLE) \
			&& echo "Signed $(BUNDLE) (ad-hoc fallback — grants won't persist across rebuilds)")
	@echo "Built $(BUNDLE)"

# Embed Sparkle.framework (with its XPC services + Updater.app) and add the rpath
# so the executable can find it inside the bundle.
embed-sparkle:
	@SPK=$$(find .build/artifacts -name Sparkle.framework -type d -path '*macos*' | head -1); \
	if [ -n "$$SPK" ]; then \
		mkdir -p $(CONTENTS)/Frameworks; \
		ditto "$$SPK" $(CONTENTS)/Frameworks/Sparkle.framework; \
		install_name_tool -add_rpath @executable_path/../Frameworks $(MACOS_DIR)/$(APP) 2>/dev/null || true; \
		echo "Embedded Sparkle.framework"; \
	else echo "Sparkle.framework not found (run swift build first)"; fi

# Regenerate AppIcon.icns from Resources/AppIcon.png when the PNG is present/newer.
icon:
	@if [ -f Resources/AppIcon.png ]; then \
		sh scripts/make-icon.sh Resources/AppIcon.png Resources/AppIcon.icns; \
	fi

sign:
	@codesign --force --deep --sign "$(CODESIGN_ID)" \
		--entitlements Resources/FlowShelf.entitlements $(BUNDLE) 2>/dev/null \
		&& echo "Signed $(BUNDLE) (identity: $(CODESIGN_ID))" \
		|| (codesign --force --deep --sign - $(BUNDLE) \
			&& echo "Signed $(BUNDLE) (ad-hoc fallback — grants won't persist across rebuilds)")

cert-help:
	@echo "Permissions persist across updates only with a STABLE signing identity."
	@echo "Create a self-signed 'FlowShelf Self-Signed' Code Signing certificate once,"
	@echo "either via Keychain Access ▸ Certificate Assistant ▸ Create a Certificate"
	@echo "(Identity: Self Signed Root, Type: Code Signing), or via openssl + security."
	@echo "It's the default CODESIGN_ID; the build falls back to ad-hoc if it's absent."

run: bundle
	@open $(BUNDLE)

# Copy into /Applications so the TCC identity + path stay stable.
install: bundle
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE)"
	@cp -R $(BUNDLE) "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(BUNDLE)"
	@open "$(INSTALL_DIR)/$(BUNDLE)"

clean:
	@rm -rf .build $(BUNDLE) dist
	@echo "Cleaned"

# ----------------------------------------------------------------------------
# Distribution: a notarized .dmg for website download.
# Requires a paid Apple Developer account ($99/yr) and:
#   DEVID  = "Developer ID Application: Your Name (TEAMID)"   (NOT "Apple Development")
#   NOTARY = a notarytool keychain profile (run `make notary-setup` once)
# Then:  make dist DEVID="Developer ID Application: Your Name (XXXXXXXXXX)"
# ----------------------------------------------------------------------------
DEVID  ?= Developer ID Application: Abu Monsur Md Moheuddin Kadery (27T48QHU7X)
NOTARY ?= flowshelf-notary
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG    := dist/$(APP)-$(VERSION).dmg

developer-id-bundle: build icon
	@test -n "$(DEVID)" || { echo 'Set DEVID="Developer ID Application: Name (TEAMID)"'; exit 1; }
	@rm -rf $(BUNDLE) && mkdir -p $(MACOS_DIR) $(CONTENTS)/Resources
	@cp $(BIN) $(MACOS_DIR)/$(APP)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns; fi
	@if [ -f Resources/buymeacoffee.png ]; then cp Resources/buymeacoffee.png $(CONTENTS)/Resources/buymeacoffee.png; fi
	@if [ -f Resources/MenuBarIcon.png ]; then cp Resources/MenuBarIcon.png $(CONTENTS)/Resources/MenuBarIcon.png; fi
	@SPK=$$(find .build/artifacts -name Sparkle.framework -type d -path '*macos*' | head -1); \
	if [ -n "$$SPK" ]; then \
		mkdir -p $(CONTENTS)/Frameworks; \
		ditto "$$SPK" $(CONTENTS)/Frameworks/Sparkle.framework; \
		install_name_tool -add_rpath @executable_path/../Frameworks $(MACOS_DIR)/$(APP) 2>/dev/null || true; \
		echo "Embedded Sparkle.framework"; \
	else echo "Sparkle.framework not found (run swift build first)"; exit 1; fi
	@echo "Signing with hardened runtime (required for notarization)…"
	@SPK="$(CONTENTS)/Frameworks/Sparkle.framework/Versions/B"; \
	if [ -d "$$SPK" ]; then \
		codesign --force --options runtime --timestamp --sign "$(DEVID)" "$$SPK/XPCServices/Installer.xpc"; \
		codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$(DEVID)" "$$SPK/XPCServices/Downloader.xpc"; \
		codesign --force --options runtime --timestamp --sign "$(DEVID)" "$$SPK/Autoupdate"; \
		codesign --force --options runtime --timestamp --sign "$(DEVID)" "$$SPK/Updater.app"; \
		codesign --force --options runtime --timestamp --sign "$(DEVID)" "$(CONTENTS)/Frameworks/Sparkle.framework"; \
	fi
	@codesign --force --options runtime --timestamp \
		--entitlements Resources/FlowShelf.entitlements \
		--sign "$(DEVID)" $(BUNDLE)
	@codesign --verify --deep --strict --verbose=2 $(BUNDLE)
	@echo "Built Developer ID app bundle → $(BUNDLE)"

dist: developer-id-bundle
	@rm -rf dist && mkdir -p dist
	@sh scripts/build-dmg.sh $(BUNDLE) "$(DMG)"
	@echo "Signing disk image…"
	@codesign --force --options runtime --timestamp \
		--sign "$(DEVID)" "$(DMG)"
	@codesign --verify --strict --verbose=2 "$(DMG)"
	@echo "Notarizing $(DMG) (this can take a few minutes)…"
	@xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY)" --wait
	@xcrun stapler staple "$(DMG)"
	@spctl -a -t open --context context:primary-signature -vv "$(DMG)" || true
	@echo "Done → $(DMG)  (upload this to your website)"

notary-setup:
	@echo "Run this once to store your notary credentials in the keychain:"
	@echo '  xcrun notarytool store-credentials "$(NOTARY)" \'
	@echo '    --apple-id YOUR_APPLE_ID --team-id TEAMID --password APP_SPECIFIC_PASSWORD'
	@echo "(Create an app-specific password at https://account.apple.com → Sign-In & Security.)"

# Free, NON-notarized .dmg (no Apple Developer account needed). Signed with the
# stable self-signed identity (CODESIGN_ID) so permissions PERSIST across updates
# and it still runs on any Mac. First launch needs System Settings ▸ Privacy &
# Security ▸ "Open Anyway" (un-notarized). Notarize (`make dist`) to remove that.
dmg: bundle
	@mkdir -p dist
	@sh scripts/build-dmg.sh $(BUNDLE) "$(DMG)"
	@echo "Wrote $(DMG)  (stable-signed; first launch via System Settings ▸ Open Anyway)"

# Publish a Developer-ID-signed, notarized DMG to GitHub Releases.
# The non-notarized `dmg` target remains available for local/test builds.
release: dist
	@sh scripts/release.sh

# Bump the app version. Usage: make set-version VER=1.1.0 [BUILD=2]
set-version:
	@test -n "$(VER)" || { echo 'Usage: make set-version VER=1.1.0 [BUILD=2]'; exit 1; }
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VER)" Resources/Info.plist
	@if [ -n "$(BUILD)" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD)" Resources/Info.plist; fi
	@echo "Version → $(VER) (build $(BUILD)). Now add a CHANGELOG.md entry for it."
