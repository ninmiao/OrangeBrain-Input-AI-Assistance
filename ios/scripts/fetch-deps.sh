#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Downloads the prebuilt iOS static libraries pinned in ios/deps.lock.json
# (fcitx5-prebuilder, MIT), verifies every tarball against its SHA-256 and
# unpacks them into ios/.deps/<variant>/{include,lib,share}.
#
#   ios/scripts/fetch-deps.sh                 # default variants from the lock file
#   ios/scripts/fetch-deps.sh os64            # device libraries only
#   ios/scripts/fetch-deps.sh sim-arm64 os64
#
# Variants: os64 = device, sim-arm64 = arm64 simulator, sim-x86_64 = Intel simulator.
# Downloads are cached in $OC_DEPS_CACHE (default ios/.deps-cache) so CI can
# cache that directory. Each file is fetched from the project's mirror release
# first and from the upstream 'ios' release second; the hash decides.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$IOS_DIR/deps.lock.json"
CACHE="${OC_DEPS_CACHE:-$IOS_DIR/.deps-cache}"
DEST_ROOT="$IOS_DIR/.deps"
VENDORED_HEADER="$IOS_DIR/Packages/OCRime/Sources/CRime/include/rime_api.h"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || PY=python

# One line per file: variant<TAB>package<TAB>suffix<TAB>sha256<TAB>upstream<TAB>mirror
plan() {
  "$PY" - "$LOCK" "$@" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf8"))
wanted = sys.argv[2:] or lock["defaultVariants"]
for variant in wanted:
    if variant not in lock["variants"]:
        sys.exit("unknown variant: " + variant)
    info = lock["variants"][variant]
    suffix = info["suffix"]
    upstream = info.get("upstream", lock["upstream"])
    prefix = info.get("mirrorPrefix", "")
    for package, entry in lock["packages"].items():
        name = f"{package}{suffix}.tar.bz2"
        print("\t".join([variant, package, name, entry[variant]["sha256"],
                         f'{upstream}/{name}', f'{lock["mirror"]}/{prefix}{name}']))
PY
}

lock_hash="$(sha256_of "$LOCK")"
variants_wanted="$("$PY" - "$LOCK" "$@" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf8"))
print(" ".join(sys.argv[2:] or lock["defaultVariants"]))
PY
)"

mkdir -p "$CACHE/dl"
for variant in $variants_wanted; do
  stamp="$DEST_ROOT/$variant/.lock-sha256"
  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$lock_hash" ] && [ -f "$DEST_ROOT/$variant/lib/librime.a" ]; then
    echo "[$variant] already unpacked for this lock file"
    continue
  fi
  rm -rf "${DEST_ROOT:?}/$variant"
  mkdir -p "$DEST_ROOT/$variant" "$CACHE/dl/$variant"

  while IFS=$'\t' read -r v package name expected upstream mirror; do
    [ "$v" = "$variant" ] || continue
    file="$CACHE/dl/$variant/$name"
    if [ -f "$file" ] && [ "$(sha256_of "$file")" != "$expected" ]; then
      echo "[$variant] cached $name has the wrong hash, downloading again"
      rm -f "$file"
    fi
    if [ ! -f "$file" ]; then
      echo "[$variant] downloading $name"
      ok=0
      for url in "$mirror" "$upstream"; do
        if curl -fsSL --retry 3 --retry-delay 2 -o "$file.part" "$url"; then
          if [ "$(sha256_of "$file.part")" = "$expected" ]; then
            mv "$file.part" "$file"; ok=1; echo "[$variant]   from $url"; break
          fi
          echo "[$variant]   hash mismatch from $url (got $(sha256_of "$file.part"), want $expected)" >&2
          rm -f "$file.part"
        fi
      done
      if [ "$ok" != 1 ]; then
        echo "ERROR: could not obtain $name with SHA-256 $expected" >&2
        exit 1
      fi
    fi
    # Boost is header-only apart from three small archives; skip its 6000 headers.
    if [ "$package" = "boost" ]; then
      tar -xjf "$file" -C "$DEST_ROOT/$variant" --exclude 'include/boost' --exclude 'include/boost/*' --exclude 'lib/cmake' --exclude 'share'
    else
      tar -xjf "$file" -C "$DEST_ROOT/$variant"
    fi
  done < <(plan "$variant")

  # The Swift package carries a copy of the C header; it must be the one the library was built with.
  expected_header="$("$PY" -c "import json,sys; print(json.load(open(sys.argv[1],encoding='utf8'))['headers']['rime_api.h'])" "$LOCK")"
  actual_header="$(sha256_of "$DEST_ROOT/$variant/include/rime_api.h")"
  vendored_header="$(sha256_of "$VENDORED_HEADER")"
  if [ "$actual_header" != "$expected_header" ] || [ "$vendored_header" != "$expected_header" ]; then
    echo "ERROR: rime_api.h mismatch: lock=$expected_header package=$actual_header vendored=$vendored_header" >&2
    echo "Copy $DEST_ROOT/$variant/include/rime_api.h to $VENDORED_HEADER and update the lock file." >&2
    exit 1
  fi

  echo "$lock_hash" > "$stamp"
  echo "[$variant] ready: $(ls "$DEST_ROOT/$variant/lib"/*.a | wc -l | tr -d ' ') static libraries"
done
