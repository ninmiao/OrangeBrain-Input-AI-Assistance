#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Turns an unsigned device build of OrangeCell.app into a sideloadable IPA.
#
#   make-ipa.sh <OrangeCell.app> <output.ipa> <ios/Config dir with the entitlements>
#
# Both bundles get an ad-hoc signature that carries the entitlements declared in
# project.yml (the App Group), because SideStore reads them from the binary when
# it registers the App IDs and App Group for the user's free Apple ID and then
# signs again on the phone. No certificate or key is involved.
set -euo pipefail

APP="$(cd "$1" && pwd)"
IPA_PATH="$2"
CONFIG="$(cd "$3" && pwd)"
APPEX="$APP/PlugIns/OrangeCellKeyboard.appex"
INFO="${CI_OUT:-.}/logs/ipa-info.txt"
mkdir -p "$(dirname "$INFO")" "$(dirname "$IPA_PATH")"
IPA_PATH="$(cd "$(dirname "$IPA_PATH")" && pwd)/$(basename "$IPA_PATH")"

[ -d "$APPEX" ] || { echo "keyboard extension missing from $APP" >&2; exit 1; }
rm -rf "$APP/_CodeSignature" "$APPEX/_CodeSignature"

codesign --force --sign - --timestamp=none --entitlements "$CONFIG/OrangeCellKeyboard.entitlements" "$APPEX"
codesign --force --sign - --timestamp=none --entitlements "$CONFIG/OrangeCell.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

work="$(mktemp -d)"
mkdir "$work/Payload"
cp -R "$APP" "$work/Payload/"
rm -f "$IPA_PATH"
(cd "$work" && zip -qry -X "$IPA_PATH" Payload)
rm -rf "$work"

{
  echo "ipa: $(basename "$IPA_PATH")  $(stat -f%z "$IPA_PATH") bytes"
  echo "sha256: $(shasum -a 256 "$IPA_PATH" | cut -d' ' -f1)"
  echo
  echo "== Info.plist (app)"
  plutil -p "$APP/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion|MinimumOSVersion|CFBundleDisplayName|DTPlatformName|DTSDKName'
  echo "== Info.plist (keyboard)"
  plutil -p "$APPEX/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion|MinimumOSVersion|CFBundleDisplayName|RequestsOpenAccess|PrimaryLanguage|IsASCIICapable|NSExtensionPointIdentifier|NSExtensionPrincipalClass'
  echo "== architectures"
  lipo -info "$APP/OrangeCell"
  lipo -info "$APPEX/OrangeCellKeyboard"
  echo "== platform"
  vtool -show-build "$APP/OrangeCell" | head -n 8
  echo "== entitlements (app)"
  codesign -d --entitlements :- "$APP" 2>/dev/null
  echo "== entitlements (keyboard)"
  codesign -d --entitlements :- "$APPEX" 2>/dev/null
  echo "== signature"
  codesign -dvv "$APP" 2>&1 | grep -E 'Identifier|Signature|Authority|TeamIdentifier|Format'
  echo "== librime linked in (symbol present)"
  nm -gU "$APPEX/OrangeCellKeyboard" 2>/dev/null | grep -c -E '_rime_get_api|_oc_invoke' || true
  echo "== payload"
  unzip -l "$IPA_PATH" | tail -n 25
} > "$INFO" 2>&1 || true
cat "$INFO"
