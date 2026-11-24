#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the Rime data that is bundled into the iOS app (docs/IOS_PLAN.md 4.3 / 4.4):
#
#   1. gathers the sources Android already ships (default.yaml, the Wanxiang
#      schema, algebra and dictionaries, the prelude punctuation / key bindings),
#      plus the small iOS customization ios/rime/default.custom.yaml;
#   2. compiles them with oc_deployer, which links the pinned macOS librime;
#   3. writes ios/.rime-data/rime-shared/{build,opencc,licenses,oc-data.json}.
#
# The keyboard only reads rime-shared (read-only inside the app bundle). It never
# deploys; a newer deployment lands in the App Group and is detected through the
# deploy stamp.
#
#   needs: ios/.deps/macos-arm64 (run ios/scripts/fetch-deps.sh macos-arm64 first)
#   output: ios/.rime-data/rime-shared  (override the parent with OC_RIME_OUT)
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$IOS_DIR/.." && pwd)"
OUT="${OC_RIME_OUT:-$IOS_DIR/.rime-data}"
ANDROID_SHARED="$REPO/android/app/src/main/assets/shared"
PRELUDE="$REPO/android/app/data/rime/prelude"
DEPS="$IOS_DIR/.deps/macos-arm64"
WORK="$OUT/work"
RESULT="$OUT/rime-shared"

[ -f "$DEPS/lib/librime.a" ] || { echo "missing $DEPS/lib/librime.a: run fetch-deps.sh macos-arm64" >&2; exit 1; }
[ -d "$ANDROID_SHARED" ] || { echo "missing $ANDROID_SHARED" >&2; exit 1; }

rm -rf "$WORK" "$RESULT"
mkdir -p "$WORK/src" "$WORK/user" "$RESULT/build"

# ---- 1. sources (copied, symlinks followed; nothing is modified) ---------------
cp -L "$ANDROID_SHARED/default.yaml" "$WORK/src/"
# In the repository the prelude files inside assets/shared are one-line pointers
# ("../../../../data/rime/prelude/x.yaml", links that lost their meaning when they were
# committed from Windows); the real files are in android/app/data/rime/prelude.
for f in key_bindings.yaml punctuation.yaml symbols.yaml; do
  cp -L "$PRELUDE/$f" "$WORK/src/"
  if head -c 3 "$WORK/src/$f" | grep -q '^\.\./'; then
    echo "ERROR: $f is a path pointer, not Rime data" >&2
    exit 1
  fi
done
cp -R -L "$ANDROID_SHARED"/orangecell_wanxiang* "$WORK/src/"
cp "$IOS_DIR/rime/default.custom.yaml" "$WORK/user/"
echo "sources:"
(cd "$WORK/src" && find . -type f | sort | head -n 40)

# ---- 2. deployer -----------------------------------------------------------------
clang -O2 -arch arm64 -mmacosx-version-min=13.3 -Wall \
  -I"$DEPS/include" "$IOS_DIR/tools/oc_deployer/oc_deployer.c" -o "$WORK/oc_deployer" \
  -Wl,-force_load,"$DEPS/lib/librime.a" \
  -L"$DEPS/lib" -lqjs -lleveldb -lglog -llua -lmarisa -lopencc -lyaml-cpp -lzstd \
  -lboost_container -lboost_iostreams -lboost_random -lboost_context -lboost_date_time \
  -lc++ -framework JavaScriptCore -framework CoreFoundation

# ---- 3. compile ------------------------------------------------------------------
start=$(date +%s)
"$WORK/oc_deployer" "$WORK/src" "$WORK/user" "$RESULT/build" 2>&1 | tee "$WORK/deployer.log"
echo "deploy took $(( $(date +%s) - start )) s"

# ---- 4. package ------------------------------------------------------------------
cp -R "$DEPS/share/opencc" "$RESULT/opencc"
# Sources of the small configuration files (a few hundred KiB), so the app can recompile
# default.yaml in the App Group after the user changed settings. The dictionary sources
# (50 MiB of text) stay out of the bundle.
for f in default.yaml key_bindings.yaml punctuation.yaml symbols.yaml orangecell_wanxiang.schema.yaml; do
  cp "$WORK/src/$f" "$RESULT/$f"
done
cp "$WORK"/src/orangecell_wanxiang_d_*_algebra.yaml "$WORK"/src/orangecell_wanxiang_d_*.dict.yaml "$RESULT/"
cp "$IOS_DIR/rime/default.custom.yaml" "$RESULT/default.custom.yaml"
mkdir -p "$RESULT/licenses/wanxiang"
cp "$ANDROID_SHARED/licenses/wanxiang/"* "$RESULT/licenses/wanxiang/"

python3 - "$WORK" "$RESULT" "$ANDROID_SHARED" "$REPO" <<'PY'
import datetime, hashlib, json, os, re, subprocess, sys

work, result, android_shared, repo = sys.argv[1:5]

def tree_hash(root):
    digest = hashlib.sha256()
    for base, _dirs, files in sorted(os.walk(root)):
        for name in sorted(files):
            path = os.path.join(base, name)
            digest.update(os.path.relpath(path, root).encode())
            with open(path, "rb") as handle:
                digest.update(hashlib.sha256(handle.read()).digest())
    return digest.hexdigest()

log = open(os.path.join(work, "deployer.log"), encoding="utf8", errors="replace").read()
match = re.search(r"librime (\S+)", log)
dictionaries = json.load(open(os.path.join(android_shared, "orangecell-dictionaries.json"), encoding="utf8"))
files = []
for base, _dirs, names in sorted(os.walk(os.path.join(result, "build"))):
    for name in sorted(names):
        path = os.path.join(base, name)
        files.append({"path": os.path.relpath(path, result), "size": os.path.getsize(path)})
stamp = {
    "format": 1,
    "builtWithLibrime": match.group(1) if match else None,
    "schema": "orangecell_wanxiang",
    "dictionary": {
        "name": "wanxiang",
        "version": dictionaries["dictionary"]["version"],
        "assetSha256": dictionaries["dictionary"]["asset"]["sha256"],
        "license": "CC BY 4.0 (amzxyz and contributors)",
    },
    "grammarModel": False,
    "inputSha256": tree_hash(os.path.join(work, "src")) + ":" + tree_hash(os.path.join(work, "user")),
    "builtAtUtc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "files": files,
}
with open(os.path.join(result, "oc-data.json"), "w", encoding="utf8") as handle:
    json.dump(stamp, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
total = sum(f["size"] for f in files)
print(f"build output: {len(files)} files, {total / 1048576:.1f} MiB")
for item in sorted(files, key=lambda f: -f["size"])[:12]:
    print(f"  {item['size'] / 1048576:8.2f} MiB  {item['path']}")
PY

# Compiled files must exist, otherwise the keyboard would fall back to deploying.
for required in default.yaml orangecell_wanxiang.schema.yaml; do
  [ -f "$RESULT/build/$required" ] || { echo "ERROR: build/$required was not produced" >&2; exit 1; }
done
ls "$RESULT/build"/*.table.bin "$RESULT/build"/*.prism.bin >/dev/null
du -sh "$RESULT"
