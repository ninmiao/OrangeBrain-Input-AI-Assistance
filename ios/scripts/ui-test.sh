#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs XCUITest classes / methods of the OCUITests scheme on the booted simulator and
# collects what they leave behind (screenshots, notes, hierarchy dumps) under $CI_OUT.
#
#   ui-test.sh <tag> <OrangeCellUITests/Class[/method]> [more -only-testing ids...]
#
# env: SIM_UDID  CI_OUT  DERIVED_DATA  [PROJECT]  [OC_RIME_SHARED]  [CONFIGURATION]
set -uo pipefail

TAG="${1:?tag}"
shift
UDID="${SIM_UDID:?SIM_UDID}"
OUT="${CI_OUT:?CI_OUT}"
DD="${DERIVED_DATA:?DERIVED_DATA}"
PROJECT="${PROJECT:-ios/OrangeCell.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SHOTS="$OUT/screenshots"
LOGS="$OUT/logs"
DIR="$OUT/ui-$TAG"
mkdir -p "$SHOTS" "$LOGS"
rm -rf "$DIR" "$RUNNER_TEMP/results/ui-$TAG.xcresult"
mkdir -p "$DIR"

only=()
for id in "$@"; do only+=("-only-testing:$id"); done

shrink() {
  local size
  size=$(wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0)
  if [ "${size:-0}" -gt 300000 ]; then sips -Z 1200 "$1" >/dev/null 2>&1 || true; fi
}

echo "[ui-test] $TAG: $*"
TEST_RUNNER_OC_SHOT_DIR="$DIR" TEST_RUNNER_OC_RIME_SHARED="${OC_RIME_SHARED:-}" TEST_RUNNER_OC_FULL_ACCESS="${OC_FULL_ACCESS:-on}" \
  xcodebuild test-without-building \
  -project "$PROJECT" -scheme OCUITests -configuration "$CONFIGURATION" \
  -destination "id=$UDID" -derivedDataPath "$DD" \
  "${only[@]}" \
  -resultBundlePath "$RUNNER_TEMP/results/ui-$TAG.xcresult" > "$LOGS/ui-$TAG.log" 2>&1
code=$?

for f in "$DIR"/*.png; do
  [ -f "$f" ] || continue
  cp "$f" "$SHOTS/$TAG-$(basename "$f")"
  shrink "$SHOTS/$TAG-$(basename "$f")"
done
for f in "$DIR"/*.txt; do
  [ -f "$f" ] && cp "$f" "$LOGS/ui-$TAG-$(basename "$f")"
done
if [ "$code" -ne 0 ]; then
  tail -n 300 "$LOGS/ui-$TAG.log" > "$LOGS/ui-$TAG.tail.txt"
  grep -n -E 'error:|failed|XCT' "$LOGS/ui-$TAG.log" | head -n 80 > "$LOGS/ui-$TAG.errors.txt" || true
else
  tail -n 30 "$LOGS/ui-$TAG.log" > "$LOGS/ui-$TAG.tail.txt"
fi
grep -E "Executed [0-9]+ tests?" "$LOGS/ui-$TAG.log" | tail -n 1 || true
# Zero executed tests or a skipped test is a failure, not a pass.
if [ "$code" -eq 0 ]; then
  python3 "$(dirname "$0")/check_tests.py" "$LOGS/ui-$TAG.log" || code=1
fi
exit "$code"
