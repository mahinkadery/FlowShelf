#!/bin/bash
# Publish a GitHub Release with the built DMG, so the website can link to a
# permanent "latest" download URL. Requires the GitHub CLI, authenticated once:
#   gh auth login
#
# Usage: scripts/release.sh            (reads version from Info.plist)
set -e

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
VDMG="dist/FlowShelf-$VERSION.dmg"
STABLE="dist/FlowShelf.dmg"          # constant name → permanent latest URL

if [ ! -f "$VDMG" ]; then echo "Build it first:  make dmg"; exit 1; fi
command -v gh >/dev/null || { echo "Install GitHub CLI: https://cli.github.com"; exit 1; }

# A constant-named asset so this URL ALWAYS serves the newest build:
#   https://github.com/<owner>/<repo>/releases/latest/download/FlowShelf.dmg
cp "$VDMG" "$STABLE"

NOTES="See the changelog: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/blob/main/CHANGELOG.md"

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$STABLE" "$VDMG" --clobber
  echo "Updated release $TAG"
else
  git tag "$TAG" 2>/dev/null || true
  git push origin "$TAG" 2>/dev/null || true
  gh release create "$TAG" "$STABLE" "$VDMG" \
    --title "FlowShelf $VERSION" --notes "$NOTES"
  echo "Created release $TAG"
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "Permanent download link for the website:"
echo "  https://github.com/$REPO/releases/latest/download/FlowShelf.dmg"
