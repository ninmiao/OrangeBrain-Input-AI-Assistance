#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rewrites ios/deps.lock.json from the current fcitx5-prebuilder `ios` release.

The SHA-256 values come from the digests GitHub computes for each release asset
(unauthenticated API, one request). Review the diff, then run ios/scripts/
fetch-deps.sh to confirm that the downloaded files really match.

    python ios/scripts/update-deps-lock.py [--mirror-tag ios-deps-YYYYMMDD]
"""
import argparse
import datetime
import json
import pathlib
import urllib.request

REPO = "fcitx-contrib/fcitx5-prebuilder"
PACKAGES = ["librime", "boost", "glog", "leveldb", "lua", "marisa", "opencc", "yaml-cpp", "zstd"]
VARIANTS = {"os64": "", "sim-arm64": "-arm64", "sim-x86_64": "-x86_64"}
LOCK = pathlib.Path(__file__).resolve().parent.parent / "deps.lock.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mirror-tag", default=None)
    args = parser.parse_args()

    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/releases/tags/ios",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "orangecell-deps-lock"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    assets = {a["name"]: a for a in release["assets"]}

    previous = json.loads(LOCK.read_text(encoding="utf8")) if LOCK.exists() else {}
    mirror_tag = args.mirror_tag or previous.get("mirrorTag") or "ios-deps-" + datetime.date.today().strftime("%Y%m%d")

    packages = {}
    for name in PACKAGES:
        entry = {}
        for variant, suffix in VARIANTS.items():
            asset = assets[f"{name}{suffix}.tar.bz2"]
            digest = asset["digest"]
            assert digest.startswith("sha256:"), digest
            entry[variant] = {"sha256": digest[len("sha256:"):], "size": asset["size"]}
        packages[name] = entry

    lock = {
        "schema": 1,
        "comment": "Prebuilt iOS static libraries from fcitx5-prebuilder (MIT). The upstream 'ios' release is rolling, so every file is pinned by SHA-256; fetch-deps.sh refuses anything else.",
        "upstream": f"https://github.com/{REPO}/releases/download/ios",
        "upstreamUpdatedAt": release.get("updated_at"),
        "mirrorTag": mirror_tag,
        "mirror": f"https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/releases/download/{mirror_tag}",
        "variants": {variant: {"suffix": suffix} for variant, suffix in VARIANTS.items()},
        "defaultVariants": ["os64", "sim-arm64"],
        "packages": packages,
        # rime_api.h in the librime tarball must be byte-identical to the copy
        # vendored in ios/Packages/OCRime (checked by fetch-deps.sh).
        "headers": previous.get("headers", {}),
    }
    LOCK.write_text(json.dumps(lock, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    print(f"wrote {LOCK}")


if __name__ == "__main__":
    main()
