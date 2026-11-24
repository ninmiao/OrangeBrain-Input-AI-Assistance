#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copies every tarball pinned in ios/deps.lock.json from the upstream
# fcitx5-prebuilder 'ios' release to this repository's release "mirrorTag", so a
# rolling upstream release can never change or break the build. Each file is
# verified against the lock file before it is uploaded.
#
#   env: GH_TOKEN (workflow GITHUB_TOKEN with contents: write), GITHUB_REPOSITORY
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$IOS_DIR/deps.lock.json"
REPO="${GITHUB_REPOSITORY:?}"
WORK="$(mktemp -d)"

TAG="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1],encoding='utf8'))['mirrorTag'])" "$LOCK")"
echo "mirror release: $TAG"

python3 - "$LOCK" > "$WORK/plan.tsv" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf8"))
for package, entry in lock["packages"].items():
    for variant, info in entry.items():
        suffix = lock["variants"][variant]["suffix"]
        name = f"{package}{suffix}.tar.bz2"
        print("\t".join([name, info["sha256"], f'{lock["upstream"]}/{name}']))
PY

while IFS=$'\t' read -r name sha url; do
  curl -fsSL --retry 3 -o "$WORK/$name" "$url"
  actual="$(sha256sum "$WORK/$name" | cut -d' ' -f1)"
  if [ "$actual" != "$sha" ]; then
    echo "ERROR: $name has SHA-256 $actual, the lock file says $sha" >&2
    exit 1
  fi
  echo "verified $name"
done < "$WORK/plan.tsv"

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$REPO" --prerelease --latest=false \
    --title "iOS prebuilt libraries $TAG" \
    --notes "Mirror of the fcitx5-prebuilder (MIT) 'ios' release files pinned by ios/deps.lock.json. See ios/ThirdPartyNotices.md for the licenses of the contained libraries."
fi
gh release upload "$TAG" "$WORK"/*.tar.bz2 --repo "$REPO" --clobber
echo "uploaded $(ls "$WORK"/*.tar.bz2 | wc -l) files to $TAG"
