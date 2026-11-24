#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Simulator end-to-end run of the real keyboard extension (docs/IOS_PLAN.md sections 6.2, 8).
#
#   phase A  keyboard enabled, no Full Access: typing through the system keyboard (nihao + candidate,
#            a sentence + space, backspace while composing, 中/EN), memory measured from outside
#   settings Settings UI: Allow Full Access
#   phase B  Full Access: the keyboard learns a phrase, the app deploys while the keyboard runs, the
#            keyboard process is killed, a new one must still offer the learned phrase first
#
# The XCUITest cannot reach into the simulator, so it asks this script (files named request-<name>
# in its result folder, answered with done-<name>) to measure `footprint`, run the app deployment
# and kill the keyboard process. Every check is written to e2e.md; the exit code is the gate.
#
# env: SIM_UDID  PRODUCTS_DIR  DERIVED_DATA  CI_OUT  [PROJECT]  [CONFIGURATION=Release]
#      [E2E_MODE=full|typing]  [FOOTPRINT_BUDGET_MB=55]
set -uo pipefail

UDID="${SIM_UDID:?SIM_UDID}"
OUT="${CI_OUT:?CI_OUT}"
PRODUCTS="${PRODUCTS_DIR:?PRODUCTS_DIR}"
export DERIVED_DATA="${DERIVED_DATA:?DERIVED_DATA}"
export PROJECT="${PROJECT:-ios/OrangeCell.xcodeproj}"
export CONFIGURATION="${CONFIGURATION:-Release}"
MODE="${E2E_MODE:-full}"
BUDGET="${FOOTPRINT_BUDGET_MB:-55}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
SHOTS="$OUT/screenshots"
LOGS="$OUT/logs"
mkdir -p "$SHOTS" "$LOGS" "${RUNNER_TEMP:-/tmp}/results"
export CI_OUT="$OUT"

APP_ID=io.github.ninmiao.orangecell
KB_ID=io.github.ninmiao.orangecell.keyboard
SIM_DATA="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data"
RESULT="$OUT/e2e.md"
FOOTPRINTS="$OUT/footprints.tsv"
: > "$RESULT"
: > "$FOOTPRINTS"
FAILURES=0

log() { echo "[e2e] $*"; }
row() { echo "| $1 | $2 |" >> "$RESULT"; log "$1: $2"; }
check() {
  # check <name> <0|1 as exit status of the condition> [detail]
  if [ "$2" -eq 0 ]; then row "$1" "PASS ${3:-}"; else row "$1" "**FAIL** ${3:-}"; FAILURES=$((FAILURES + 1)); fi
}

shrink() {
  local size
  size=$(wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0)
  if [ "${size:-0}" -gt 300000 ]; then sips -Z 1200 "$1" >/dev/null 2>&1 || true; fi
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

keyboard_pid() { pgrep -f "OrangeCellKeyboard.appex/OrangeCellKeyboard" | head -n 1; }

newest() {
  # newest file with this name anywhere in the simulator containers
  find "$SIM_DATA/Containers" -name "$1" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n 1
}

group_directory() {
  local meta
  meta="$(find "$SIM_DATA/Containers/Shared/AppGroup" -maxdepth 2 -name '.com.apple.mobile_container_manager.metadata.plist' -print0 2>/dev/null \
    | xargs -0 grep -l 'group.io.github.ninmiao.orangecell' 2>/dev/null | head -n 1)"
  if [ -n "$meta" ]; then dirname "$meta"; fi
}

footprint_mb() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf8", errors="replace").read()
m = re.search(r"Footprint:\s*([\d.]+)\s*(KB|MB|GB)", text)
if not m:
    print("n/a")
else:
    value = float(m.group(1)); unit = m.group(2)
    print(round(value / 1024 if unit == "KB" else value * 1024 if unit == "GB" else value, 1))
PY
}

# ------------------------------------------------------------------ helper requests of the UI test

measure_footprint() {
  local label="$1" pid mb
  pid="$(keyboard_pid || true)"
  if [ -z "$pid" ]; then
    row "footprint $label" "keyboard process not running"
    printf '%s\tn/a\n' "$label" >> "$FOOTPRINTS"
    return
  fi
  footprint "$pid" > "$LOGS/footprint-$label.txt" 2>&1 || true
  vmmap -summary "$pid" > "$LOGS/vmmap-$label.txt" 2>&1 || true
  mb="$(footprint_mb "$LOGS/footprint-$label.txt")"
  printf '%s\t%s\n' "$label" "$mb" >> "$FOOTPRINTS"
  row "keyboard process footprint after $label ($CONFIGURATION, pid $pid)" "$mb MB"
}

read_stamp() {
  local group
  group="$(group_directory)"
  if [ -n "$group" ] && [ -f "$group/state/deploy-stamp" ]; then cat "$group/state/deploy-stamp"; fi
}

deploy_from_app() {
  local marker="$OUT/.deploy-marker" before after result waited=0 ok changed
  before="$(read_stamp)"
  touch "$marker"
  sleep 1
  xcrun simctl launch "$UDID" "$APP_ID" -OCDeploy >/dev/null 2>&1
  result=""
  while [ "$waited" -lt 90 ]; do
    result="$(find "$SIM_DATA/Containers" -name deploy-result.json -newer "$marker" 2>/dev/null | head -n 1)"
    [ -n "$result" ] && break
    sleep 1
    waited=$((waited + 1))
  done
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  after="$(read_stamp)"
  if [ -n "$result" ]; then cp "$result" "$LOGS/deploy-result.json"; fi
  ok=1
  if [ -n "$result" ] && grep -q '"success" *: *true' "$result"; then ok=0; fi
  check "app deployment while the keyboard runs" "$ok" "(${waited}s)"
  changed=1
  if [ -n "$after" ] && [ "$after" != "$before" ]; then changed=0; fi
  check "deploy stamp changed" "$changed" "(before: ${before:-none}, after: ${after:-none})"
}

kill_keyboard() {
  local pid
  pid="$(keyboard_pid || true)"
  if [ -z "$pid" ]; then row "kill keyboard process" "not running"; return; fi
  kill -9 "$pid" 2>/dev/null || true
  sleep 2
  row "kill keyboard process" "killed pid $pid"
}

serve_requests() {
  local dir="$1" request name
  for request in "$dir"/request-*; do
    [ -e "$request" ] || continue
    name="${request##*/request-}"
    [ -e "$dir/done-$name" ] && continue
    log "request: $name"
    case "$name" in
      footprint-*) measure_footprint "${name#footprint-}" ;;
      deploy) deploy_from_app ;;
      kill-keyboard) kill_keyboard ;;
      *) row "unknown request" "$name" ;;
    esac
    : > "$dir/done-$name"
  done
}

# run_ui_test <tag> <OrangeCellUITests/Class[/method]>; returns the exit code of the tests
run_ui_test() {
  local tag="$1" target="$2" pid code
  bash "$SCRIPTS/ui-test.sh" "$tag" "$target" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    serve_requests "$OUT/ui-$tag"
    sleep 1
  done
  wait "$pid"
  code=$?
  return "$code"
}

collect_reports() {
  # collect_reports <tag>: the keyboard and app reports as they are now
  local keyboard app
  keyboard="$(newest report-keyboard.json || true)"
  app="$(newest report-app.json || true)"
  if [ -n "$keyboard" ]; then cp "$keyboard" "$LOGS/report-keyboard-$1.json"; fi
  if [ -n "$app" ]; then cp "$app" "$LOGS/report-app-$1.json"; fi
}

json_field() {
  # json_field <file> <key>  -> value or empty
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    value = json.load(open(sys.argv[1], encoding="utf8")).get(sys.argv[2])
except Exception:
    value = None
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

list_userdb() {
  # list_userdb <tag>: where the user dictionary files ended up
  {
    echo "== App Group rime-user"
    local group
    group="$(group_directory)"
    if [ -n "$group" ]; then ls -lR "$group/rime-user" 2>/dev/null | head -n 80; fi
    echo "== keyboard private Application Support rime-user"
    find "$SIM_DATA/Containers/Data/PluginKitPlugin" -type d -name rime-user 2>/dev/null | while read -r dir; do
      echo "$dir"
      ls -lR "$dir" 2>/dev/null | head -n 80
    done
  } > "$LOGS/userdb-$1.txt" 2>&1
}

# ---------------------------------------------------------------------------------- start

{
  echo "### Simulator end-to-end ($CONFIGURATION, $MODE)"
  echo
  echo "| step | result |"
  echo "| --- | --- |"
} >> "$RESULT"

if [ ! -d "$PRODUCTS/OrangeCell.app" ] || [ ! -d "$PRODUCTS/OCTestHost.app" ]; then
  row "products" "missing OrangeCell.app or OCTestHost.app in $PRODUCTS"
  exit 2
fi

boot
shot "e2e-00-springboard"
if ! xcrun simctl install "$UDID" "$PRODUCTS/OrangeCell.app"; then row "install OrangeCell.app" "FAILED"; exit 2; fi
if ! xcrun simctl install "$UDID" "$PRODUCTS/OCTestHost.app"; then row "install OCTestHost.app" "FAILED"; exit 2; fi
row "install" "ok (app with keyboard extension, test host)"

# The app leaves its probe file and key sample in the App Group when asked to.
xcrun simctl launch "$UDID" "$APP_ID" -OCRunSelfTest >/dev/null 2>&1
sleep 6
xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true

# Make the system offer our keyboard (docs/IOS_PLAN.md section 8, method 1): the entry is the
# extension's bundle id. Two more keyboards are listed, so the system asks for a globe key.
xcrun simctl spawn "$UDID" defaults write -g AppleKeyboards -array "$KB_ID" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" > "$LOGS/seed.txt" 2>&1
xcrun simctl spawn "$UDID" defaults write -g AppleKeyboardsExpanded -int 1 >> "$LOGS/seed.txt" 2>&1
reboot

# ---------------------------------------------------------------- phase A: no Full Access
NAME_A="phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN)"
if run_ui_test "typing" "OrangeCellUITests/KeyboardUITests/testRealExtensionTypesChineseAndEnglish"; then
  check "$NAME_A" 0
else
  check "$NAME_A" 1 "(see ui-typing logs and screenshots)"
fi
collect_reports "A"
list_userdb "A"
if [ -f "$LOGS/report-keyboard-A.json" ]; then
  fa="$(json_field "$LOGS/report-keyboard-A.json" fullAccess)"
  shared="$(json_field "$LOGS/report-keyboard-A.json" userDataShared)"
  running="$(json_field "$LOGS/report-keyboard-A.json" rimeRunning)"
  version="$(json_field "$LOGS/report-keyboard-A.json" rimeDataDictionary)"
  row "keyboard report (A)" "fullAccess=$fa userDataShared=$shared rimeRunning=$running dictionary=$version"
  c=1; [ "$running" = "true" ] && c=0
  check "phase A: engine running inside the extension" "$c"
  c=1; [ "$shared" = "false" ] && c=0
  check "phase A: without Full Access the user dictionary is private" "$c" "(userDataShared=$shared)"
else
  check "phase A: keyboard report exists" 1 "(the extension never wrote report-keyboard.json)"
fi

if [ "$MODE" = "full" ]; then
  # ------------------------------------------------------------ Full Access through Settings
  if run_ui_test "settings-fullaccess" "OrangeCellUITests/EnableKeyboardUITests"; then
    check "Settings UI: Allow Full Access" 0
  else
    check "Settings UI: Allow Full Access" 1 "(see ui-settings-fullaccess logs)"
  fi
  reboot

  # ---------------------------------------------- phase B: learning, deployment, restart
  NAME_B="phase B: learn 拟好, app deploys, keyboard restarts, 拟好 is still first"
  if run_ui_test "learn" "OrangeCellUITests/KeyboardUITests/testUserDictionaryAcrossDeployAndKeyboardRestart"; then
    check "$NAME_B" 0
  else
    check "$NAME_B" 1 "(see ui-learn logs and screenshots)"
  fi
  collect_reports "B"
  list_userdb "B"
  if [ -f "$LOGS/report-keyboard-B.json" ]; then
    fa="$(json_field "$LOGS/report-keyboard-B.json" fullAccess)"
    shared="$(json_field "$LOGS/report-keyboard-B.json" userDataShared)"
    running="$(json_field "$LOGS/report-keyboard-B.json" rimeRunning)"
    stamp="$(json_field "$LOGS/report-keyboard-B.json" deployStamp)"
    row "keyboard report (B)" "fullAccess=$fa userDataShared=$shared rimeRunning=$running deployStamp=$stamp"
    c=1; [ "$shared" = "true" ] && c=0
    check "phase B: with Full Access the user dictionary is in the App Group" "$c" "(userDataShared=$shared)"
    # What the extension itself reports (report-keyboard.json), the checks the first end-to-end run lacked.
    python3 - "$LOGS/report-keyboard-B.json" > "$LOGS/report-checks.txt" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf8"))
modules = report.get("rimeModules") or []
store = [p for p in report.get("keyStorage") or [] if p.get("backend") == "encrypted-file"]
checks = [
    ("oc_core round trip inside the extension", report.get("ocCoreOK") is True),
    ("librime modules registered (lua, octagram, predict, qjs)", all(m in modules for m in ("lua", "octagram", "predict", "qjs"))),
    ("Rime data stamp readable and built by the linked librime", report.get("rimeDataBuiltWithLibrime") == report.get("rimeVersion")),
    ("the extension sees the app probe file (App Group shared)", report.get("peerProbe") is not None),
    ("encrypted-file key store readable across processes", bool(store) and store[0].get("crossProcessReadOK") is True),
]
for name, ok in checks:
    print(("PASS" if ok else "FAIL") + "\t" + name)
PY
    while IFS=$'\t' read -r verdict name; do
      c=1; [ "$verdict" = "PASS" ] && c=0
      check "phase B: $name" "$c"
    done < "$LOGS/report-checks.txt"
  else
    check "phase B: keyboard report exists" 1
  fi
  group="$(group_directory)"
  c=1
  if [ -n "$group" ] && ls "$group"/rime-user/*.userdb/CURRENT >/dev/null 2>&1; then c=0; fi
  check "phase B: user dictionary files present in the App Group" "$c"
fi

# ------------------------------------------------------------------ the app pages, for the screenshots
xcrun simctl launch --terminate-running-process "$UDID" "$APP_ID" >/dev/null 2>&1
sleep 4
shot "e2e-app-home"
xcrun simctl launch --terminate-running-process "$UDID" "$APP_ID" -OCOpenDiagnostics >/dev/null 2>&1
sleep 5
shot "e2e-app-diagnostics"
xcrun simctl launch --terminate-running-process "$UDID" "$APP_ID" -OCOpenLicenses >/dev/null 2>&1
sleep 4
shot "e2e-app-licenses"

# ------------------------------------------------------------------ memory gate
typing_mb="$(awk -F'\t' '$1 == "typing" {print $2}' "$FOOTPRINTS" | head -n 1)"
worst_mb="$(awk -F'\t' '$2 != "n/a" && $2 + 0 > m {m = $2 + 0} END {print m + 0}' "$FOOTPRINTS")"
echo "${typing_mb:-n/a}" > "$OUT/footprint-keyboard-mb.txt"
if [ "$CONFIGURATION" = "Release" ]; then
  c=1
  if [ -n "$typing_mb" ] && [ "$typing_mb" != "n/a" ] && awk -v v="$typing_mb" -v b="$BUDGET" 'BEGIN { exit !(v + 0 <= b + 0) }'; then c=0; fi
  check "memory budget: keyboard footprint after typing <= $BUDGET MB" "$c" "(measured ${typing_mb:-n/a} MB, highest of all measurements ${worst_mb:-n/a} MB)"
else
  row "memory (Debug, information only)" "after typing ${typing_mb:-n/a} MB, highest ${worst_mb:-n/a} MB"
fi

# OS log and crash reports of the run
xcrun simctl spawn "$UDID" log show --last 30m --style compact \
  --predicate 'process == "OrangeCellKeyboard" OR process == "OrangeCell" OR subsystem == "com.apple.PlugInKit"' \
  2>/dev/null | tail -n 400 > "$LOGS/sim-oslog-tail.txt" || true
for crash in $(find "$HOME/Library/Logs/DiagnosticReports" -name 'OrangeCell*' -mmin -90 2>/dev/null | head -n 5); do
  cp "$crash" "$LOGS/crash-$(basename "$crash")"
done

row "failed checks" "$FAILURES"
exit "$FAILURES"
