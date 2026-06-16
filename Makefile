APP        := FlowShelf
BUNDLE     := $(APP).app
CONFIG     := release
BIN        := .build/$(CONFIG)/$(APP)
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
INSTALL_DIR := /Applications

# Code-signing identity. A STABLE identity is important: ad-hoc ("-") changes the
# signature every build, so macOS resets Accessibility/Screen-Recording grants on
# each rebuild. We default to this Mac's Apple Development identity (stable team
# id → grants persist). Override with `CODESIGN_ID=-` for ad-hoc, or another hash.
# The sign step falls back to ad-hoc if this identity is unavailable.
CODESIGN_ID ?= E1474BAEE61438AB92BACD718B0B8A2A9FAE853B

.PHONY: all build bundle sign run clean install

all: bundle

build:
	swift build -c $(CONFIG)

bundle: build icon
	@rm -rf $(BUNDLE)
	@mkdir -p $(MACOS_DIR) $(CONTENTS)/Resources
	@cp $(BIN) $(MACOS_DIR)/$(APP)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns; fi
	@$(MAKE) sign
	@echo "Built $(BUNDLE)"

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
	@echo "To make permissions persist across rebuilds, create a stable identity once:"
	@echo "  1. Open Keychain Access → menu: Keychain Access ▸ Certificate Assistant ▸"
	@echo "     Create a Certificate…"
	@echo "  2. Name: FlowShelf   Identity Type: Self Signed Root"
	@echo "     Certificate Type: Code Signing   → Create"
	@echo "  3. Then:  make install CODESIGN_ID=\"FlowShelf\""
	@echo "  4. Grant Accessibility + Screen Recording to FlowShelf once; they'll stick."

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
DEVID  ?=
NOTARY ?= flowshelf-notary
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG    := dist/$(APP)-$(VERSION).dmg

dist: build icon
	@test -n "$(DEVID)" || { echo 'Set DEVID="Developer ID Application: Name (TEAMID)"'; exit 1; }
	@rm -rf $(BUNDLE) dist && mkdir -p $(MACOS_DIR) $(CONTENTS)/Resources dist
	@cp $(BIN) $(MACOS_DIR)/$(APP)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	@echo "Signing with hardened runtime (required for notarization)…"
	@codesign --force --deep --options runtime --timestamp \
		--entitlements Resources/FlowShelf.entitlements \
		--sign "$(DEVID)" $(BUNDLE)
	@codesign --verify --strict --verbose=2 $(BUNDLE)
	@sh scripts/build-dmg.sh $(BUNDLE) "$(DMG)"
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

# Free, NON-notarized .dmg (no Apple Developer account needed). It works, but on
# download users get a Gatekeeper warning and must right-click → Open once.
dmg: bundle
	@mkdir -p dist
	@sh scripts/build-dmg.sh $(BUNDLE) "$(DMG)"
	@echo "Wrote $(DMG)  (NOT notarized — first launch needs right-click ▸ Open)"

# Bump the app version. Usage: make set-version VER=1.1.0 [BUILD=2]
set-version:
	@test -n "$(VER)" || { echo 'Usage: make set-version VER=1.1.0 [BUILD=2]'; exit 1; }
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VER)" Resources/Info.plist
	@if [ -n "$(BUILD)" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD)" Resources/Info.plist; fi
	@echo "Version → $(VER) (build $(BUILD)). Now add a CHANGELOG.md entry for it."
