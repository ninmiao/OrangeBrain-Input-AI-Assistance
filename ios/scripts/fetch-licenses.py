#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Downloads the full license texts of the third-party code that ships inside the iOS app
into ios/Resources/licenses/<id>/ (committed; the app bundles the folder and shows it on
the Acknowledgements page). Re-run when a component or its version changes.

    python ios/scripts/fetch-licenses.py
"""
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "licenses"

# id -> list of (file name, [candidate URLs])
SOURCES = {
    "librime": [("LICENSE.txt", ["https://raw.githubusercontent.com/rime/librime/master/LICENSE"])],
    "librime-lua": [("LICENSE.txt", ["https://raw.githubusercontent.com/hchunhui/librime-lua/master/LICENSE"])],
    "librime-octagram": [("LICENSE.txt", ["https://raw.githubusercontent.com/lotem/librime-octagram/master/LICENSE"])],
    "librime-predict": [("LICENSE.txt", ["https://raw.githubusercontent.com/rime/librime-predict/master/LICENSE"])],
    "librime-qjs": [("LICENSE.txt", [
        "https://raw.githubusercontent.com/HuangJian/librime-qjs/main/LICENSE",
        "https://raw.githubusercontent.com/HuangJian/librime-qjs/master/LICENSE",
    ])],
    "quickjs-ng": [("LICENSE.txt", ["https://raw.githubusercontent.com/quickjs-ng/quickjs/master/LICENSE"])],
    "boost": [("LICENSE.txt", ["https://raw.githubusercontent.com/boostorg/boost/master/LICENSE_1_0.txt"])],
    "glog": [("LICENSE.txt", ["https://raw.githubusercontent.com/google/glog/v0.7.1/COPYING"])],
    "leveldb": [("LICENSE.txt", ["https://raw.githubusercontent.com/google/leveldb/main/LICENSE"])],
    "marisa-trie": [("COPYING.md", ["https://raw.githubusercontent.com/s-yata/marisa-trie/master/COPYING.md"])],
    "opencc": [
        ("LICENSE.txt", ["https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE"]),
        ("NOTICE.txt", ["https://raw.githubusercontent.com/BYVoid/OpenCC/master/NOTICE"]),
    ],
    "yaml-cpp": [("LICENSE.txt", ["https://raw.githubusercontent.com/jbeder/yaml-cpp/master/LICENSE"])],
    "zstd": [("LICENSE.txt", ["https://raw.githubusercontent.com/facebook/zstd/dev/LICENSE"])],
    "fcitx5-prebuilder": [("LICENSE.txt", ["https://raw.githubusercontent.com/fcitx-contrib/fcitx5-prebuilder/master/LICENSE"])],
}

LUA_LICENSE = """Lua is distributed under the terms of the MIT license.

Copyright (C) 1994-2024 Lua.org, PUC-Rio.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
"""


def fetch(urls):
    last = None
    for url in urls:
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "orangecell-licenses"})
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            last = f"{url}: {error}"
    raise SystemExit(f"could not download any of {urls}: {last}")


def main() -> None:
    for component, files in SOURCES.items():
        folder = ROOT / component
        folder.mkdir(parents=True, exist_ok=True)
        for name, urls in files:
            try:
                data = fetch(urls)
            except SystemExit as error:
                if name == "NOTICE.txt":
                    print(f"  {component}/{name}: no NOTICE upstream ({error})")
                    continue
                raise
            (folder / name).write_bytes(data)
            print(f"{component}/{name}: {len(data)} bytes")
    lua = ROOT / "lua"
    lua.mkdir(parents=True, exist_ok=True)
    (lua / "LICENSE.txt").write_text(LUA_LICENSE, encoding="utf8")
    print("lua/LICENSE.txt: written (MIT, from lua.org/license.html)")


if __name__ == "__main__":
    sys.exit(main())
