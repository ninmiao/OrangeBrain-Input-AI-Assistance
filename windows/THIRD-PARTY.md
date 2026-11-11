# Windows third-party components

- **Weasel**: https://github.com/rime/weasel, source commit `f96ed24a8a535961b6ffc7160d98851a69cee4f8`, GPL-3.0-or-later. Native sources are retained under `native/`, with Zephyr changes in the same tree. Upstream license: `native/LICENSE.txt`.
- **librime 1.17.0**: https://github.com/rime/librime, official Windows MSVC binary commit `33e7814`, BSD-3-Clause; full source and license are also retained in the Android native tree. The release contains its linked open-source dependencies.
- **Rime Ice dictionaries**: https://github.com/iDvel/rime-ice; reuse the project's existing source dictionaries and notices from `android/app/src/main/assets/shared/licenses`. Windows copies these files at package time.
- **OpenCC**: https://github.com/BYVoid/OpenCC, Apache-2.0. Windows config uses shipped text dictionaries; these are also shared with Android.
- **Boost 1.89**: https://www.boost.org, Boost Software License 1.0. Development sources/build products are excluded from publishing.
- **WTL / ATL**: WTL headers retained with Weasel source; Microsoft ATL is a Visual Studio development dependency and is not committed as source.
- **OkHttp 4.12 / Okio**: https://github.com/square/okhttp and https://github.com/square/okio, Apache-2.0; shared cancellable HTTPS transport.
- **Kotlin, kotlinx.coroutines, kotlinx.serialization**: Apache-2.0. **JNA**: LGPL-2.1-or-later / Apache-2.0, using the Apache-2.0 option.
- **OpenJDK runtime**: GPLv2 with Classpath Exception. Runtime legal notices are included in the generated app image.

Zephyr source remains GPL-3.0-or-later. Distributors must retain notices and provide corresponding source for covered components; this document does not replace their licenses. No API credentials are included in source or packages.
