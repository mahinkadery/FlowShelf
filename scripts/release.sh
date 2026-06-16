#!/bin/bash
# Publish a release: upload the DMG to GitHub Releases AND generate a Sparkle
# appcast so existing users get an in-app "update available" prompt.
# One-time setup:
#   - gh auth login
#   - create + push the GitHub repo (gh repo create)
#   - set Info.plist SUFeedURL to: https://raw.githubusercontent.com/<owner>/FlowShelf/main/appcast.xml
# Usage: scripts/release.sh
set -e

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
VDMG="dist/FlowShelf-$VERSION.dmg"
STABLE="dist/FlowShelf.dmg"          # constant name → permanent "latest" URL

[ -f "$VDMG" ] || { echo "Build it first:  make dmg"; exit 1; }
command -v gh >/dev/null || { echo "Install GitHub CLI: https://cli.github.com"; exit 1; }
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
  || { echo "Create & push the GitHub repo first (e.g. gh repo create)"; exit 1; }

GEN="$(find .build/artifacts -name generate_appcast | head -1)"
[ -n "$GEN" ] || { echo "Run 'swift build' once to fetch the Sparkle tools."; exit 1; }

cp "$VDMG" "$STABLE"

# 1) Generate a SIGNED appcast whose enclosure points at the permanent latest URL.
TMP="$(mktemp -d)"; cp "$STABLE" "$TMP/"
"$GEN" "$TMP" --download-url-prefix "https://github.com/$REPO/releases/latest/download/"
cp "$TMP/appcast.xml" appcast.xml
rm -rf "$TMP"

# 2) Publish the appcast on the main branch (SUFeedURL serves it raw).
git add appcast.xml
git commit -q -m "Update appcast for $VERSION" 2>/dev/null || true
git push origin HEAD 2>/dev/null || true

# 3) Upload the DMGs to a GitHub Release.
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$STABLE" "$VDMG" --clobber
  echo "Updated release $TAG"
else
  git tag "$TAG" 2>/dev/null || true
  git push origin "$TAG" 2>/dev/null || true
  gh release create "$TAG" "$STABLE" "$VDMG" --title "FlowShelf $VERSION" --notes-file CHANGELOG.md
  echo "Created release $TAG"
fi

echo
echo "Download link for the website:  https://github.com/$REPO/releases/latest/download/FlowShelf.dmg"
echo "Set Info.plist SUFeedURL to:    https://raw.githubusercontent.com/$REPO/main/appcast.xml"
