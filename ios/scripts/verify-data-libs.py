#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Checks that the compiled Rime data was made with the librime files deps.lock.json pins.

    verify-data-libs.py <rime-shared dir> <deps.lock.json>

The data is compiled by the macOS librime and read by the iOS one; they are different upstream builds. A
cached data bundle from before a lock change must not slip into an IPA.
"""
import json
import pathlib
import sys

shared, lock_path = (pathlib.Path(a) for a in sys.argv[1:3])
stamp = json.loads((shared / "oc-data.json").read_text(encoding="utf8"))
lock = json.loads(lock_path.read_text(encoding="utf8"))
libraries = stamp.get("libraries")
if not libraries:
    sys.exit("oc-data.json has no `libraries` record: rebuild the data")
errors = []
if libraries["compiledWithMacosLibrimeSha256"] != lock["packages"]["librime"]["macos-arm64"]["sha256"]:
    errors.append("compiled with a macOS librime that is not the pinned one")
for variant, sha in libraries["linkedIosLibrimeSha256"].items():
    if sha != lock["packages"]["librime"][variant]["sha256"]:
        errors.append(f"iOS librime {variant} differs from the lock")
if errors:
    sys.exit("verify-data-libs: " + "; ".join(errors))
print("verify-data-libs: the data matches the pinned librime files "
      f"(macOS {libraries['compiledWithMacosLibrimeSha256'][:12]}, iOS {', '.join(k + ' ' + v[:12] for k, v in libraries['linkedIosLibrimeSha256'].items())})")
