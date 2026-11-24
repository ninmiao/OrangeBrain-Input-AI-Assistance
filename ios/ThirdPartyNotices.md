# iOS 版第三方声明

橘脑一颗 iOS 版自有代码使用 GPL-3.0-or-later（与项目一致）。下面列出随 iOS 安装包分发或被源码引用的第三方部件及其许可证。许可证名称取自各上游仓库首页的标注；上架前逐项核对原文见 `docs/IOS_PLAN.md` 第 10 节。

## 随包的静态库（fcitx5-prebuilder，`ios/deps.lock.json` 锁定 SHA-256）

静态库由 [fcitx5-prebuilder](https://github.com/fcitx-contrib/fcitx5-prebuilder)（MIT）为 iOS 预编译，构建脚本里的补丁（竖排、选项持久化等）由其维护。键盘扩展与主应用链接下列库：

| 部件 | 许可证 | 上游 |
| --- | --- | --- |
| librime（含 lua / octagram / predict / qjs 插件） | BSD-3-Clause | https://github.com/rime/librime |
| librime-lua | BSD-3-Clause | https://github.com/hchunhui/librime-lua |
| librime-octagram | BSD-3-Clause | https://github.com/lotem/librime-octagram |
| librime-predict | BSD-3-Clause | https://github.com/rime/librime-predict |
| librime-qjs | BSD-3-Clause | https://github.com/HuangJian/librime-qjs |
| Boost（仅 container / iostreams / random 三个库） | BSL-1.0 | https://www.boost.org |
| glog | BSD-3-Clause | https://github.com/google/glog |
| LevelDB | BSD-3-Clause | https://github.com/google/leveldb |
| Lua | MIT | https://www.lua.org |
| marisa-trie | BSD-2-Clause 或 LGPL-2.1（双许可） | https://github.com/s-yata/marisa-trie |
| OpenCC | Apache-2.0 | https://github.com/BYVoid/OpenCC |
| yaml-cpp | MIT | https://github.com/jbeder/yaml-cpp |
| zstd | BSD-3-Clause 或 GPL-2.0（双许可，取 BSD） | https://github.com/facebook/zstd |

另外：`shared/native-core/third_party/nlohmann/json.hpp`（nlohmann/json 3.12.0，MIT）编入 AI 核心，原文见该目录的 `LICENSE.MIT`。

## 随源码复制的文件

`ios/Packages/OCRime/Sources/CRime/include/rime_api.h` 是 librime 随预编译包发布的 C 头文件，原样复制（`ios/scripts/fetch-deps.sh` 会校验它与下载包里的文件逐字节相同）。librime 的许可证原文保存在 `ios/Packages/OCRime/Sources/CRime/LICENSE-librime.txt`，内容如下：

```
Copyright (c) 2014, RIME Developers
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## 构建工具与参考（不随包）

- fcitx5-prebuilder（MIT）：预编译库的来源，许可证原文如下。

```
MIT License

Copyright (c) 2023-2024 fcitx contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- XcodeGen（MIT）：只在 CI 里生成工程，不随包。
- 仓输入法 Hamster（MIT）的 RimeKit / HamsterKeyboardKit：M0 没有拷入任何代码；以后移植时在这里补充版权声明与原文。
- fcitx5-ios、Squirrel、Trime（GPL）：只阅读思路，没有拷入代码。
