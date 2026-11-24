#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs the pinned XcodeGen release (a zip from the project's GitHub release, checked
# against a SHA-256 written down here) instead of `brew install`, so the tool that
# generates the Xcode project cannot change under a build.
#
#   install-xcodegen.sh [destination dir]      (default: ios/.tools/xcodegen)
#
# In GitHub Actions the bin directory is also added to PATH. To update: take the new
# release's xcodegen.zip digest from its GitHub release page and change the two lines below.
set -euo pipefail

VERSION="2.48.0"
SHA256="620c9f0dc10849f94728ab5df52d225ebab8187439dd6fee1925e59e80dff892"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$IOS_DIR/.tools/xcodegen}"
CACHE="${OC_DEPS_CACHE:-$IOS_DIR/.deps-cache}/tools"
ZIP="$CACHE/xcodegen-$VERSION.zip"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

mkdir -p "$CACHE"
if [ -f "$ZIP" ] && [ "$(sha256_of "$ZIP")" != "$SHA256" ]; then rm -f "$ZIP"; fi
if [ ! -f "$ZIP" ]; then
  curl -fsSL --retry 3 --retry-delay 2 -o "$ZIP.part" "$URL"
  if [ "$(sha256_of "$ZIP.part")" != "$SHA256" ]; then
    echo "ERROR: xcodegen.zip has SHA-256 $(sha256_of "$ZIP.part"), expected $SHA256" >&2
    rm -f "$ZIP.part"
    exit 1
  fi
  mv "$ZIP.part" "$ZIP"
fi

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$ZIP" -d "$DEST"
BIN="$DEST/xcodegen/bin"
chmod +x "$BIN/xcodegen"
"$BIN/xcodegen" --version
if [ -n "${GITHUB_PATH:-}" ]; then echo "$BIN" >> "$GITHUB_PATH"; fi
echo "xcodegen $VERSION installed in $BIN"
