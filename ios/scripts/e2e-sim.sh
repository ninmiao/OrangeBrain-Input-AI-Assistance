#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Simulator end-to-end run for the keyboard extension (docs/IOS_PLAN.md sections
# 6.2 and 8): install the app, make the system offer OrangeCell's keyboard,
# type into OCTestHost, take screenshots, read the extension's own diagnostics
# report and measure its memory footprint from outside.
#
# Enabling a third-party keyboard in the simulator is tried in the order the plan
# gives: (1) pre-seed AppleKeyboards in the global preferences, (2) drive the
# Settings app with XCUITest. Everything each attempt does is logged.
#
# env: SIM_UDID  PRODUCTS_DIR  DERIVED_DATA  CI_OUT  [PROJECT]
set -uo pipefail

UDID="${SIM_UDID:?SIM_UDID}"
OUT="${CI_OUT:?CI_OUT}"
PRODUCTS="${PRODUCTS_DIR:?PRODUCTS_DIR}"
DD="${DERIVED_DATA:?DERIVED_DATA}"
PROJECT="${PROJECT:-ios/OrangeCell.xcodeproj}"
SHOTS="$OUT/screenshots"
LOGS="$OUT/logs"
mkdir -p "$SHOTS" "$LOGS"

APP_ID=io.github.ninmiao.orangecell
KB_ID=io.github.ninmiao.orangecell.keyboard
HOST_ID=io.github.ninmiao.orangecell.testhost
SIM_DATA="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data"
RESULT="$OUT/e2e.md"
: > "$RESULT"

log() { echo "[e2e] $*"; }
row() { echo "| $1 | $2 |" >> "$RESULT"; log "$1: $2"; }

shrink() {
  local size
  size=$(wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0)
  if [ "$size" -gt 300000 ]; then sips -Z 1200 "$1" >/dev/null 2>&1 || true; fi
}

shot() {
  local file="$SHOTS/$1.png"
  if xcrun simctl io "$UDID" screenshot --type=png "$file" >/dev/null 2>&1; then shrink "$file"; else log "screenshot $1 failed"; fi
}

boot() {
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
}

reboot() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  boot
}

dump_prefs() {
  local tag="$1"
  {
    echo "== defaults read -g AppleKeyboards"
    xcrun simctl spawn "$UDID" defaults read -g AppleKeyboards 2>&1
    echo "== defaults read -g (keyboard related lines)"
    xcrun simctl spawn "$UDID" defaults read -g 2>&1 | grep -i -E 'keyboard|input|AppleLanguages|AppleLocale'
    echo "== preference files mentioning keyboards"
    find "$SIM_DATA/Library/Preferences" -maxdepth 1 -iname '*eyboard*' 2>/dev/null
    echo "== pluginkit"
    xcrun simctl spawn "$UDID" pluginkit -mAD -p com.apple.keyboard-service 2>&1 | head -n 40
    echo "== preference files that mention orangecell (Full Access and friends)"
    local plist
    for plist in "$SIM_DATA"/Library/Preferences/*.plist; do
      if plutil -p "$plist" 2>/dev/null | grep -q -i orangecell; then
        echo "--- $plist"
        plutil -p "$plist" 2>/dev/null | grep -i -B2 -A2 orangecell | head -n 30
      fi
    done
    echo "== com.apple.keyboard.preferences.plist"
    plutil -p "$SIM_DATA/Library/Preferences/com.apple.keyboard.preferences.plist" 2>&1 | head -n 40
  } > "$LOGS/prefs-$tag.txt" 2>&1
}

keyboard_pid() {
  pgrep -f "OrangeCellKeyboard.appex/OrangeCellKeyboard" | head -n 1
}

newest_report() {
  # newest report-<role>.json anywhere in the simulator's containers
  find "$SIM_DATA/Containers" -name "report-$1.json" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n 1
}

# run_ui_test <Class[/method]> <tag>  -> exit code of xcodebuild
run_ui_test() {
  local target="$1"
  local tag="$2"
  local dir="$OUT/ui-$tag"
  rm -rf "$dir" "$OUT/results-ui-$tag.xcresult"
  mkdir -p "$dir"
  log "UI test $target ($tag)"
  TEST_RUNNER_OC_SHOT_DIR="$dir" xcodebuild test-without-building \
    -project "$PROJECT" -scheme OCUITests \
    -destination "id=$UDID" -derivedDataPath "$DD" \
    -only-testing:"OrangeCellUITests/$target" \
    -resultBundlePath "$OUT/results-ui-$tag.xcresult" > "$LOGS/ui-$tag.log" 2>&1
  local code=$?
  local f
  for f in "$dir"/*.png; do
    [ -f "$f" ] || continue
    cp "$f" "$SHOTS/$tag-$(basename "$f")"
    shrink "$SHOTS/$tag-$(basename "$f")"
  done
  for f in "$dir"/*.txt; do
    [ -f "$f" ] && cp "$f" "$LOGS/ui-$tag-$(basename "$f")"
  done
  if [ "$code" -ne 0 ]; then
    tail -n 300 "$LOGS/ui-$tag.log" > "$LOGS/ui-$tag.tail.txt"
    grep -n -E 'error:|failed|XCT' "$LOGS/ui-$tag.log" | head -n 80 > "$LOGS/ui-$tag.errors.txt" || true
  else
    tail -n 30 "$LOGS/ui-$tag.log" > "$LOGS/ui-$tag.tail.txt"
  fi
  rm -rf "$OUT/results-ui-$tag.xcresult"
  return "$code"
}

launch_host() {
  xcrun simctl launch --terminate-running-process "$UDID" "$HOST_ID" >/dev/null 2>&1
}

collect_os_logs() {
  xcrun simctl spawn "$UDID" log show --last 10m --style compact \
    --predicate 'process == "OrangeCellKeyboard" OR process == "OrangeCell" OR subsystem == "com.apple.PlugInKit" OR process == "keyboardd"' \
    2>/dev/null | tail -n 400 > "$LOGS/sim-oslog-tail.txt" || true
  local crash
  for crash in $(find "$HOME/Library/Logs/DiagnosticReports" -name 'OrangeCell*' -mmin -60 2>/dev/null | head -n 5); do
    cp "$crash" "$LOGS/crash-$(basename "$crash")"
  done
}

# ---------------------------------------------------------------- start
{
  echo "### Simulator end-to-end"
  echo
  echo "| step | result |"
  echo "| --- | --- |"
} >> "$RESULT"

if [ ! -d "$PRODUCTS/OrangeCell.app" ]; then
  row "products" "missing $PRODUCTS/OrangeCell.app"
  exit 2
fi

boot
xcrun simctl list devices | grep -F "$UDID" > "$LOGS/sim-device.txt" || true
shot "00-springboard"
dump_prefs "00-initial"

if ! xcrun simctl install "$UDID" "$PRODUCTS/OrangeCell.app"; then
  row "install OrangeCell.app" "FAILED"
  exit 2
fi
row "install OrangeCell.app (with keyboard extension)" "ok"
if xcrun simctl install "$UDID" "$PRODUCTS/OCTestHost.app"; then row "install OCTestHost.app" "ok"; else row "install OCTestHost.app" "FAILED"; fi
ls "$PRODUCTS/OrangeCell.app/PlugIns" > "$LOGS/appex-list.txt" 2>&1 || true

# Run the app once so it leaves its probe file and key-storage sample in the
# shared container; the keyboard's report then shows whether it can see them.
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null 2>&1
sleep 6
xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true

# --------------------------------------------- method 1: seed preferences
xcrun simctl spawn "$UDID" defaults write -g AppleKeyboards -array "$KB_ID" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" > "$LOGS/seed.txt" 2>&1
xcrun simctl spawn "$UDID" defaults write -g AppleKeyboardsExpanded -int 1 >> "$LOGS/seed.txt" 2>&1
reboot
dump_prefs "01-after-seed"
launch_host
sleep 8
shot "01-host-after-seed"

ENABLED_BY="none"

# Settings flow: adds the keyboard when it is not listed yet and switches on Full Access.
settings_flow() {
  local tag="$1"
  if run_ui_test "EnableKeyboardUITests" "$tag"; then
    row "Settings UI (add keyboard, Allow Full Access)" "PASS"
  else
    row "Settings UI (add keyboard, Allow Full Access)" "FAIL (see ui-$tag logs)"
  fi
}

if run_ui_test "KeyboardUITests" "seed"; then
  ENABLED_BY="method 1 (AppleKeyboards pre-seeded)"
  row "method 1: seed AppleKeyboards, our keyboard shown and typed into OCTestHost (XCUITest)" "PASS"
  # Full Access is needed for App Group / network access from the extension.
  dump_prefs "02-before-settings-ui"
  settings_flow "settings-fullaccess"
  dump_prefs "03-after-settings-ui"
  reboot
  launch_host
  sleep 8
  shot "02-host-after-fullaccess"
  if run_ui_test "KeyboardUITests" "fullaccess"; then
    row "with Full Access: typing into OCTestHost" "PASS"
  else
    row "with Full Access: typing into OCTestHost" "FAIL"
  fi
else
  row "method 1: seed AppleKeyboards, our keyboard shown and typed into OCTestHost (XCUITest)" "FAIL (see ui-seed logs)"
  # ------------------------------------------ method 2: drive Settings
  xcrun simctl spawn "$UDID" defaults delete -g AppleKeyboards >/dev/null 2>&1 || true
  xcrun simctl spawn "$UDID" defaults delete -g AppleKeyboardsExpanded >/dev/null 2>&1 || true
  reboot
  dump_prefs "02-before-settings-ui"
  settings_flow "settings"
  dump_prefs "03-after-settings-ui"
  reboot
  launch_host
  sleep 8
  shot "02-host-after-settings"
  if run_ui_test "KeyboardUITests" "settings-then-type"; then
    ENABLED_BY="method 2 (Settings UI)"
    row "method 2: type in OCTestHost with the enabled keyboard" "PASS"
  else
    row "method 2: type in OCTestHost with the enabled keyboard" "FAIL"
  fi
fi
row "keyboard enabled by" "$ENABLED_BY"

# ---------------------------------------------- footprint and reports
launch_host
sleep 10
shot "03-host-keyboard-final"
PID="$(keyboard_pid || true)"
if [ -n "${PID:-}" ]; then
  footprint "$PID" > "$LOGS/footprint-keyboard.txt" 2>&1 || true
  vmmap -summary "$PID" > "$LOGS/vmmap-keyboard.txt" 2>&1 || true
  FP_MB="$(python3 - "$LOGS/footprint-keyboard.txt" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf8", errors="replace").read()
m = re.search(r"Footprint:\s*([\d.]+)\s*(KB|MB|GB)", text)
if not m:
    print("n/a")
else:
    value = float(m.group(1)); unit = m.group(2)
    print(round(value / 1024 if unit == "KB" else value * 1024 if unit == "GB" else value, 1))
PY
)"
  echo "$FP_MB" > "$OUT/footprint-keyboard-mb.txt"
  row "keyboard process footprint (macOS footprint, pid $PID)" "$FP_MB MB"
else
  row "keyboard process footprint" "keyboard process not running"
fi

# The app's diagnostics screen, straight to the page.
xcrun simctl launch --terminate-running-process "$UDID" "$APP_ID" -OCOpenDiagnostics >/dev/null 2>&1
sleep 7
shot "04-app-diagnostics"
xcrun simctl launch --terminate-running-process "$UDID" "$APP_ID" >/dev/null 2>&1
sleep 3
shot "05-app-home"

KB_REPORT="$(newest_report keyboard || true)"
APP_REPORT="$(newest_report app || true)"
if [ -n "${KB_REPORT:-}" ]; then cp "$KB_REPORT" "$LOGS/report-keyboard.json"; fi
if [ -n "${APP_REPORT:-}" ]; then cp "$APP_REPORT" "$LOGS/report-app.json"; fi
row "keyboard diagnostics report" "$([ -n "${KB_REPORT:-}" ] && echo found || echo MISSING)"
row "app diagnostics report" "$([ -n "${APP_REPORT:-}" ] && echo found || echo MISSING)"

collect_os_logs

if [ "$ENABLED_BY" = "none" ]; then exit 1; fi
exit 0
