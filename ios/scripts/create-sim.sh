#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Creates a fresh "iPhone 17" simulator on the newest installed iOS runtime and
# exports its id as SIM_UDID (GITHUB_ENV in CI). A fresh device guarantees that
# no keyboard or Settings state from an earlier run is left over.
#
#   create-sim.sh [device name]
set -euo pipefail

NAME="${1:-OC-iPhone17}"

RUNTIME="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]]
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(runtimes[-1]["identifier"])
')"
DEVICE_TYPE="$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
types = json.load(sys.stdin)["devicetypes"]
exact = [t for t in types if t["name"] == "iPhone 17"]
phones = [t for t in types if t["name"].startswith("iPhone")]
print((exact or phones)[-1]["identifier"])
')"
echo "runtime:     $RUNTIME"
echo "device type: $DEVICE_TYPE"
UDID="$(xcrun simctl create "$NAME" "$DEVICE_TYPE" "$RUNTIME")"
echo "udid:        $UDID"
echo "SIM_UDID=$UDID" >> "${GITHUB_ENV:-/dev/null}"
