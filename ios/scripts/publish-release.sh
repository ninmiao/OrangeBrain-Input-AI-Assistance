#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Replaces the `ios-nightly` GitHub prerelease with the new IPA and writes the
# SideStore source JSON next to the job results (ci_publish.py then copies it to
# the ci-results branch). Uses only the workflow's GITHUB_TOKEN (gh reads GH_TOKEN).
#
#   env: OC_VERSION GITHUB_RUN_NUMBER GITHUB_REPOSITORY GITHUB_SHA CI_OUT GH_TOKEN
set -euo pipefail

IPA="dist-ipa/OrangeCell-iOS-${OC_VERSION:?}.ipa"
REPO="${GITHUB_REPOSITORY:?}"
SOURCE_URL="https://raw.githubusercontent.com/$REPO/ci-results/sidestore/source.json"

ls -l dist-ipa
python3 ios/scripts/make-source.py --ipa "$IPA" --version "$OC_VERSION" --build "${GITHUB_RUN_NUMBER:?}" \
  --tag ios-nightly --repo "$REPO" --commit "${GITHUB_SHA:?}" --out "${CI_OUT:?}/sidestore/source.json"

# Delete and recreate so the tag follows the commit; the asset URL stays the same.
gh release delete ios-nightly --repo "$REPO" --cleanup-tag --yes || true
gh release create ios-nightly "$IPA" --repo "$REPO" --target "$GITHUB_SHA" --prerelease \
  --title "iOS nightly (M0 diagnostics preview)" \
  --notes "Unsigned IPA for SideStore, built from $GITHUB_SHA (run $GITHUB_RUN_NUMBER). Add the source $SOURCE_URL in SideStore, or open the IPA with SideStore directly."
gh release view ios-nightly --repo "$REPO" --json url,assets --jq '{url: .url, assets: [.assets[].name]}'
echo "SideStore source: $SOURCE_URL (published by the publish-results job)"
