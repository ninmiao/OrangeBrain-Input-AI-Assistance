#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Publishes the new IPA to the `ios-nightly` GitHub prerelease and writes the SideStore
# source JSON next to the job results (ci_publish.py then copies it to the ci-results
# branch). Uses only the workflow's GITHUB_TOKEN (gh reads GH_TOKEN).
#
# Safe against cancelled runs: the new asset is uploaded first (its name carries the
# version, so it never replaces the file the current source points to), the tag moves
# afterwards, and only assets older than the newest three are removed. SideStore can
# therefore always download whatever the published source.json says.
#
#   env: OC_VERSION GITHUB_RUN_NUMBER GITHUB_REPOSITORY GITHUB_SHA CI_OUT GH_TOKEN
set -euo pipefail

IPA="dist-ipa/OrangeCell-iOS-${OC_VERSION:?}.ipa"
REPO="${GITHUB_REPOSITORY:?}"
TAG=ios-nightly
SOURCE_URL="https://raw.githubusercontent.com/$REPO/ci-results/sidestore/source.json"
SOURCE="${CI_OUT:?}/sidestore/source.json"

# An older run that gets here late must not replace the published build of a newer one.
published_build="$(curl -fsSL "$SOURCE_URL" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["apps"][0]["versions"][0]["buildVersion"])' 2>/dev/null || echo 0)"
if [ "${published_build:-0}" -gt "${GITHUB_RUN_NUMBER:?}" ] 2>/dev/null; then
  echo "build $published_build is already published; this run ($GITHUB_RUN_NUMBER) leaves it alone"
  exit 0
fi

ls -l dist-ipa
python3 ios/scripts/make-source.py --ipa "$IPA" --version "$OC_VERSION" --build "${GITHUB_RUN_NUMBER:?}" \
  --tag "$TAG" --repo "$REPO" --commit "${GITHUB_SHA:?}" \
  --entitlements-json dist-ipa/entitlements.json --out "$SOURCE"

# The entitlements are a decision, not an observation: the signed binaries and the SideStore source must both
# equal the committed list (ios/expected-entitlements.json). A change needs a deliberate edit of that file.
python3 - "$SOURCE" dist-ipa/entitlements.json ios/expected-entitlements.json <<'PY'
import json, sys
source = json.load(open(sys.argv[1], encoding="utf8"))
carried = sorted(json.load(open(sys.argv[2], encoding="utf8")))
expected = sorted(json.load(open(sys.argv[3], encoding="utf8")))
declared = sorted(source["apps"][0]["appPermissions"]["entitlements"])
if carried != expected:
    sys.exit(f"the app carries {carried} but ios/expected-entitlements.json says {expected}")
if declared != expected:
    sys.exit(f"source.json declares {declared} but ios/expected-entitlements.json says {expected}")
print("entitlements (carried, declared, expected):", expected)
PY

NOTES="Unsigned IPA for SideStore, built from $GITHUB_SHA (run $GITHUB_RUN_NUMBER, version $OC_VERSION). Add the source $SOURCE_URL in SideStore, or open the IPA with SideStore directly."
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$IPA" --repo "$REPO" --clobber
  gh api --method PATCH "repos/$REPO/git/refs/tags/$TAG" -f sha="$GITHUB_SHA" -F force=true >/dev/null
  gh release edit "$TAG" --repo "$REPO" --prerelease --title "iOS nightly $OC_VERSION" --notes "$NOTES"
else
  gh release create "$TAG" "$IPA" --repo "$REPO" --target "$GITHUB_SHA" --prerelease \
    --title "iOS nightly $OC_VERSION" --notes "$NOTES"
fi

# Keep the newest three IPAs so an older source.json keeps working for a while.
gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' | grep '^OrangeCell-iOS-.*\.ipa$' | sort -V \
  | head -n -3 | while read -r old; do
      echo "removing old asset $old"
      gh release delete-asset "$TAG" "$old" --repo "$REPO" --yes
    done
gh release view "$TAG" --repo "$REPO" --json url,assets --jq '{url: .url, assets: [.assets[].name]}'
echo "SideStore source: $SOURCE_URL (published by the publish-results job)"
