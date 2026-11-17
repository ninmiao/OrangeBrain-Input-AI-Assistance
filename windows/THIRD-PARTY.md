# Windows third-party components

- **Weasel**: https://github.com/rime/weasel, source commit `f96ed24a8a535961b6ffc7160d98851a69cee4f8`, GPL-3.0-or-later. Native sources are retained under `native/`, with Zephyr changes in the same tree. Upstream license: `native/LICENSE.txt`.
- **librime 1.17.0**: https://github.com/rime/librime, official Windows MSVC binary commit `33e7814`, BSD-3-Clause; full source and license are also retained in the Android native tree. The release contains its linked open-source dependencies.
- **Wanxiang dictionaries / full-pinyin algebra / grammar model**: https://github.com/amzxyz/rime-wanxiang and https://github.com/amzxyz/rime-wanxiang-data, CC BY 4.0, amzxyz and contributors. Dictionaries and pinyin algebra are bundled; the grammar model is downloaded separately. Zephyr adapts schema and file paths. Full license in shared resources and the user data directory. Upstream updater tools are not reused.
- **Rime Ice dictionaries**: https://github.com/iDvel/rime-ice; reuse the project's existing source dictionaries and notices from `android/app/src/main/assets/shared/licenses`. Windows copies these files at package time.
- **OpenCC**: https://github.com/BYVoid/OpenCC, Apache-2.0. Windows config uses shipped text dictionaries; these are also shared with Android.
- **Boost 1.89**: https://www.boost.org, Boost Software License 1.0. Development sources/build products are excluded from publishing.
- **WTL / ATL**: WTL headers retained with Weasel source; Microsoft ATL is a Visual Studio development dependency and is not committed as source.

Zephyr original source remains GPL-3.0-or-later; see [the project licensing notice](../LICENSE-NOTICE.md). Rime Ice dictionaries retain GPL-3.0-only; the project grant does not relicense them. Distributors must retain notices and provide corresponding source for covered components; this document does not replace their licenses. No API credentials are included in source or packages.

## nlohmann/json

Version 3.12.0, MIT. Used by the C++ AI core. Source: https://github.com/nlohmann/json . License is included as `licenses/nlohmann-json-MIT.txt`.

## miniz

Version 3.0.2, MIT. Only the native DEFLATE decompressor is compiled into the Windows application for dictionary ZIP files. Source: https://github.com/richgel999/miniz/tree/3.0.2 . Unmodified upstream source is in `app/third_party/miniz`; license is shipped as `licenses/miniz-MIT.txt`.
