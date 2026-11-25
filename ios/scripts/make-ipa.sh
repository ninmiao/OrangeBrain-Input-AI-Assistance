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
# The IPA must carry the compiled Rime data, the licence texts and the icon: without the data the keyboard
# would be an empty shell that still installs.
for required in rime-shared/oc-data.json rime-shared/default.yaml rime-shared/build/default.yaml                 rime-shared/build/orangecell_wanxiang.schema.yaml licenses/index.json Assets.car; do
  [ -f "$APP/$required" ] || { echo "ERROR: $required is missing from the app bundle" >&2; exit 1; }
done
ls "$APP"/rime-shared/build/*.table.bin "$APP"/rime-shared/build/*.prism.bin >/dev/null   || { echo "ERROR: the compiled dictionary (table.bin / prism.bin) is missing" >&2; exit 1; }
rm -rf "$APP/_CodeSignature" "$APPEX/_CodeSignature"

codesign --force --sign - --timestamp=none --entitlements "$CONFIG/OrangeCellKeyboard.entitlements" "$APPEX"
codesign --force --sign - --timestamp=none --entitlements "$CONFIG/OrangeCell.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# The entitlements the signed app and extension really carry. SideStore refuses an install
# when the source does not declare them all (appPermissions.entitlements), except the
# team and application identifiers it fills in itself, so make-source.py takes this file.
ENTITLEMENTS_JSON="$(dirname "$IPA_PATH")/entitlements.json"
python3 - "$APP" "$APPEX" "$ENTITLEMENTS_JSON" <<'PY'
import json, plistlib, subprocess, sys

app, appex, out = sys.argv[1:4]
FILLED_IN_BY_SIDESTORE = {"application-identifier", "com.apple.developer.team-identifier"}


def entitlement_keys(path):
    raw = subprocess.run(["codesign", "-d", "--entitlements", ":-", path], capture_output=True, check=True).stdout
    return set(plistlib.loads(raw)) - FILLED_IN_BY_SIDESTORE if raw.strip() else set()


keys_app, keys_appex = entitlement_keys(app), entitlement_keys(appex)
print("app entitlements   :", sorted(keys_app))
print("appex entitlements :", sorted(keys_appex))
with open(out, "w", encoding="utf8") as handle:
    json.dump(sorted(keys_app | keys_appex), handle, indent=2)
    handle.write("\n")
PY

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
# The info file is evidence, so it has to say what it should: errors above must not pass silently.
for expected in 'CFBundleIdentifier' 'RequestsOpenAccess' 'arm64' 'com.apple.security.application-groups' 'Signature=adhoc'; do
  grep -q "$expected" "$INFO" || { echo "ERROR: $expected is not in $INFO" >&2; exit 1; }
done
