# Zephyr Input licensing notice · 许可证声明

SPDX-License-Identifier: GPL-3.0-or-later

Copyright (C) 2026 Zephyr Input contributors, for their respective original contributions.
Original upstream copyrights and attribution remain with their respective holders.

## Project grant / 项目授权

Except where a file or component states otherwise, Zephyr Input's original code and original documentation are licensed under the GNU General Public License, version 3 or, at your option, any later version published by the Free Software Foundation (**GPL-3.0-or-later**). The complete GPL version 3 text is in [LICENSE](LICENSE). This notice applies the license to Zephyr's original contributions; it does not replace the license text or relicense third-party material.

除文件或组件另有声明外，Zephyr Input 的原创代码和原创文档采用 **GNU GPL 第 3 版或任何后续版本（GPL-3.0-or-later）**。完整 GPL 第 3 版正文见 [LICENSE](LICENSE)。本声明明确原创贡献的授权范围，不修改 GPL 正文，也不重新授权第三方材料。

The software is provided without warranty, to the extent permitted by applicable law, as set out in the GPL. The following notes summarize the license; the license itself governs.

软件在法律允许的范围内按 GPL 的规定不提供担保。以下为说明，具体权利与义务以许可证正文为准。

## What this means / 可以怎样使用

- You may use, study, modify, and redistribute the covered work, including commercially. GPL is not a non-commercial license.
- When distributing covered source or binaries, retain required copyright, license, and modification notices and fulfill the GPL's corresponding-source requirements. A binary download alone is not a substitute for corresponding source and required build materials.
- Private use or private changes do not, by themselves, require publishing your changes. Distribution obligations are governed by the GPL; this project does not add an AGPL-style network-use condition.

- 可以使用、研究、修改和再分发，包括商业使用；GPL 不是“禁止商用”许可证。
- 对外分发受 GPL 覆盖的源码或二进制时，须保留要求的版权、许可与修改声明，并按 GPL 提供对应源码及所需构建材料，不能仅提供安装包。
- 仅个人使用或私下修改，本身不要求公开修改。分发义务以 GPL 为准，本项目不额外添加 AGPL 式的网络使用条款。

## Third-party scope / 第三方适用范围

This repository is not uniformly licensed under a single license. Preserve every component's own license and notices:

| Component / 组件 | License / 许可证 | Retained notice / 保留声明 |
| --- | --- | --- |
| Trime-derived Android code / 同文 Android 基础 | GPL-3.0-or-later | Original source headers and [GPL text](LICENSE) |
| Weasel-derived Windows code / 小狼毫 Windows 基础 | GPL-3.0-or-later | [Windows native license](windows/native/LICENSE.txt), source headers and [component notes](windows/THIRD-PARTY.md) |
| Rime Ice dictionaries / 雾凇词库 | GPL-3.0-only, per the vendored upstream declaration | [NOTICE](android/app/src/main/assets/shared/licenses/rime-ice/NOTICE.txt), [LICENSE](android/app/src/main/assets/shared/licenses/rime-ice/LICENSE.txt), dictionary headers |
| librime | BSD-3-Clause | [LICENSE](android/app/src/main/jni/librime/LICENSE) |
| OpenCC | Apache-2.0 | [LICENSE](android/app/src/main/jni/OpenCC/LICENSE) |
| Boost | BSL-1.0 | [LICENSE](android/app/src/main/jni/boost/LICENSE_1_0.txt) |
| Other libraries, data, and bundled runtime / 其他库、数据和运行时 | Their respective licenses / 各自许可证 | [README acknowledgements](README.md), [Windows third-party notes](windows/THIRD-PARTY.md), component LICENSE/NOTICE files and bundled runtime legal directory |

**The Rime Ice files remain GPL-3.0-only.** “Or later” in Zephyr's own grant does not extend to those files. Where a combined covered work includes GPL-3.0-only material, GPL version 3 is the common version; do not assume that the whole combination can be distributed under a later GPL version. Mere aggregation and combined works are distinguished by the GPL.

**雾凇词库仍为 GPL-3.0-only。** Zephyr 原创部分的“或后续版本”不扩大这些文件的授权；若构成包含 GPL-3.0-only 材料的受覆盖组合作品，共同适用版本为 GPL 第 3 版，不能据此宣称整套组合作品自动获得后续版本授权。单纯集合与组合作品的区别以 GPL 为准。

API services and remote model access are subject to their providers' terms. This project license does not grant rights to OpenAI/OpenRouter services, third-party model weights, trademarks, or other third-party assets beyond their own grants.

API 服务及远程模型访问遵循提供商条款；本许可证不额外授予 OpenAI/OpenRouter 服务、第三方模型权重、商标或其他第三方资产的权利。

## References / 官方参考

- [GNU GPL v3 text](https://www.gnu.org/licenses/gpl-3.0.html)
- [GNU license recommendations](https://www.gnu.org/licenses/license-recommendations.html)
- [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html)
