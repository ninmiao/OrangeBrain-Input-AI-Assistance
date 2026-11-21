# 万象拼音接入评估

日期：2026-11-16。评估对象：OrangeCell Windows 1.6.3 / Android 1.5.3。

> 后续决定（2026-11-16）：按用户要求，语法模型改为默认开启、点击后下载，不内置安装包。两端更新功能与验证见 [万象更新说明](../rime/wanxiang-updates.md)。下文保留本次独立研究时的结论与数据。

## 结论

**可以接入，也适合成为 OrangeCell 的默认本地拼音来源。建议默认接入万象 Base 的词库与全拼转写规则，保留 OrangeCell 的界面和操作方式；大体积语法模型作为可选增强，雾凇保留为可切换方案。**

这不是建议把万象完整发布包直接覆盖到用户目录。本次已用 OrangeCell 现有 Windows librime 实际编译、加载和比较四种方案，确认词库、全拼纠错规则、Grammar 模型和分段选词能够运行。尚未修改两端应用默认方案，尚未构建新 APK/Setup，也没有修改当前安装、Policy、Key 或云端请求逻辑。Android 本轮完成源码兼容性检查，尚未进行新词库的模拟器测试。

## 1. 万象实际提供了什么

| 部分 | 作用 | 对 OrangeCell 的价值 |
| --- | --- | --- |
| 字词库、读音、词频 | 决定本地能选到哪些字词，以及基本顺序 | 可替换当前雾凇词库，改善部分日常表达、专名和读音 |
| 全拼转写规则 | 将带调字典编码转换为用户键入的普通拼音，也派生简拼和部分错拼 | 无需用户输入声调；能修复规则覆盖的字母错序 |
| Octagram `.gram` 模型 | 对当前拼音所组成的词语路径进行本地统计评分 | 改善部分同音歧义、口语片段和整句排序 |
| Lua 功能 | 英文处理、反查、声调筛选、计算器、日期、用户排序等 | 可以分项选用，需要与 OrangeCell 前端适配 |

这里的 Grammar 是本地统计语言模型，并不是要部署一个 Gemini、Qwen 或 DeepSeek。它通过 Rime 的 Octagram 插件和内存映射文件参与候选评分，不需要 API Key、GPU 或逐次网络调用。本轮离线对比没有调用任何模型 API。[词库与模型说明](https://github.com/amzxyz/rime-wanxiang/blob/wanxiang/docs/doc/dict_gram.md)、[模型项目](https://github.com/amzxyz/rime-wanxiang-data)。

它也不能替代我们的在线 LLM：规则覆盖之外的漏输、邻键误触、重复输入、开放式中英混输和颜表情生成，仍然是两类不同的问题。上游全拼规则实际包含 `nihoa`、`zhogn` 等对应音节的错序派生；模糊音另有可选规则，不能把“支持模糊音”理解为任意拼写错误都能修复。[全拼规则源码](https://github.com/amzxyz/rime-wanxiang/blob/v18.1.13/wanxiang_algebra.yaml)、[模糊音配置](https://github.com/amzxyz/rime-wanxiang/blob/wanxiang/docs/doc/fuzzy.md)。

## 2. 版本与数据体积

本次固定使用稳定发布 `v18.1.13`，没有用会持续变化的 nightly。对应提交 `9704d41ee6e52bac3f66618a267826d360aa64ee`。[发布页](https://github.com/amzxyz/rime-wanxiang/releases/tag/v18.1.13)。

| 文件或组合 | 本次核对的实际大小 |
| --- | --- |
| `rime-wanxiang-base.zip` | 26,197,573 bytes，约 25.0 MiB；不含语法模型 |
| 主词典实际引用的七份词表 | 56,874,871 bytes，约 54.2 MiB |
| 七份词表有效记录 | 1,745,171 行；包含不同读音等，不是去重词语数量 |
| `wanxiang-lts-zh-hans.gram` | 407,160,876 bytes，约 388.3 MiB |

词表是 `zi / jichu / cuoyin / duoyin / diming / mingren / yiren`。医学、化学等扩展不必全部加载。词条数比当前雾凇集成的 1,873,813 行少，并不代表效果更差；不同词频和切词方式会影响结果。

简体模型取自数据仓库的 LTS 发布，资产更新时间为 2026-11-14 UTC。LTS 标签会复用，集成必须同时锁定摘要，不能只记 `LTS` 名字。[模型资产](https://github.com/amzxyz/rime-wanxiang-data/releases/tag/LTS)。

```text
Base ZIP SHA256
2a94c48aa51eab2de20b4fdc89e065c05c828875b2bb3336a680f7c140ef088d

简体 Grammar SHA256
d4f64356231764ff27b79c9b0db79cd9d665013464cf5544e2fbd9a71e0f1c5a
```

上游把 Grammar 列为完整万象发行方案的必装组件。本文提出的“默认词库和规则、模型可选”是 **OrangeCell 自己的适配方式**，不能宣称等同完整万象体验，也不能把它误称为上游 Lite。Base/Lite/Pure/Pro 的侧重点分别是完整常规方案、裁剪部分功能的无调方案、无 Lua 的兼容方案、双拼辅助码增强方案；“Pure”并不自动意味着不需要 Grammar。[版本选择](https://github.com/amzxyz/rime-wanxiang#readme)。

## 3. 已完成的实测

### 方法与范围

- 在独立目录中使用 OrangeCell 当前 Windows `rime.dll`，实际版本 1.17.0；未访问已安装输入法的用户词库。
- DLL SHA256：`86b4c7357d4c6d293ce5589b234d8859ca2ac30923a03bedfa3926eeaf97fb0b`。
- 30 条专门对照输入，加现有人工回归集中的 30 条中文输入，共 60 条记录。其中 11 条超过 50 个字符，最长 149 个字符。部分输入重复，用于延续旧回归；这不是 60 个独立随机样本。
- 对每条输入逐步调用 `set_input`，每次读取候选，模拟 Windows 当前刷新方式。每个方案累计 2,100 个前缀状态，共四个方案。
- 空格统一转换为分词用的单引号，符合当前 Windows 适配器；主翻译器关闭用户词频学习，避免个人历史影响结果。
- 直接比较整条首选文本，评分忽略空白和 Unicode 标点；有多个期望结果时接受其一。这个标准对本来需要分段选择的输入较严格。
- **没有运行在线 AI，也不是整套输入法 UI 测试。** 原版 Base 的比较同样通过 OrangeCell 使用的 `set_input` 路径，不等于逐项测试原版的键盘 Lua 功能。这个集合刻意包含错拼、混输和历史难例，不能当成日常输入的总体准确率。

### 汇总

| 本地方案 | 首选整句匹配 | 前七候选有完整期望 | 每次刷新 P50 | P95 | 本轮最大值 | 结束时工作集 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 当前 OrangeCell 雾凇 | 21 / 60 | 24 / 60 | 0.46 ms | 11.12 ms | 24.91 ms | 48.0 MiB |
| 万象词库＋全拼规则，无 Grammar | 26 / 60 | 28 / 60 | 1.64 ms | 37.81 ms | 61.29 ms | 58.5 MiB |
| 同一适配方案＋Grammar | 25 / 60 | 27 / 60 | 1.91 ms | 41.77 ms | 65.40 ms | 188.7 MiB |
| 上游 Base＋Grammar＋Lua | 25 / 60 | 27 / 60 | 4.01 ms | 44.47 ms | 66.75 ms | 262.8 MiB |

数据来自最终一轮同顺序测试，可能受操作系统缓存及调度影响；工作集不是模型文件大小，也不是 Android 内存结论。这里只能说明此次样例下的取舍，不足以断言某套词库整体优于另一套。万象增加的拼写路径也会增加候选计算量：即使不加载模型，长输入前缀的开销也明显高于当前方案，正式默认切换前需要继续优化和测量。

### 直接可见的收益与退步

| 输入 | 当前雾凇首选 | 万象词库＋规则 | 再加 Grammar |
| --- | --- | --- | --- |
| `nihoa` | 你会哦啊 | 你好 | 你好 |
| `zhogn guo` | 中欧跟你过 | 中国 | 中国 |
| `jian ge jidan` | 间隔鸡蛋 | 煎个鸡蛋 | 煎个鸡蛋 |
| `wozhuzailiwu` | 我住在礼物 | 我住在礼物 | 我住在里屋 |
| `geixinrenjieshao` | 给信任介绍 | 给信任介绍 | 给新人介绍 |
| `shuohaojianfeiyouchileliangwanfan` | 说好减肥有吃了两碗饭 | 说好减肥又吃了两碗饭 | 说好减肥有吃了两碗饭 |
| `xianzaishurufahouxuanyouwenti` | 现在输入法候选有问题 | 现在输入法候选有问题 | 现在输入法后悬有问题 |

`nihso`、`woxiangchi hanabo`、漏掉 `w` 的 `xianzaishurufahouxuanyouenti`，没有仅凭万象得到目标首选。`nihaoo` 首选依然可能是“你好哦”，而“你好”在后续候选里：输入法无法仅凭字串确定用户是否确实要“哦”。复杂中英混输也没有因整体加载 Base 自动解决。

### 分段选择与繁简

四个方案都能通过原生 API 选择“现在”，不立刻提交整条输入；随后用同样的原始输入刷新，预编辑仍保留“现在＋后续拼音”。这证明之前修复的“先选一段，保留后面输入”路径在引擎层能够兼容万象。

适配方案保留 `traditionalization` 开关，切换后 `ruanjian` 得到“軟件”。原版 Base 使用 `s2t/s2hk/s2tw`，向它发送 OrangeCell 现有的 `traditionalization` 不会产生同样效果，需要适配。分段选择兼容通过不代表同音排序正确，两者分别检查。

原生探针源码保留在 [wanxiang_probe.cpp](../../tests/rime/wanxiang_probe.cpp)。其中所有输入前缀在 UTF-8 字符边界截断，包含人工集里的直接汉字输入。原始候选、逐条耗时和评分见 [结果 JSON](wanxiang-results-2026-11-16.json)；完整输入记录另存于 [测试集](../../tests/corpus/wanxiang-evaluation-2026-11-16.tsv)。现有 464,693 条生成语料未修改，SHA256 仍为 `d1a3d880eb3ca85d2a204b100b77b7d884817c31752294cf6ecdf1722d777e5d`。

## 4. 与当前代码的具体连接点

| 位置 | 当前情况 | 集成时需要做什么 |
| --- | --- | --- |
| Android `assets/shared/rime_ai_simp.schema.yaml` | 引用雾凇词库，只有较少简拼和 ü/v 规则 | 新增独立 `orangecell_wanxiang` 方案，使用万象词典及匹配的转写规则 |
| Android `jni/cmake/Rime.cmake`、`librime_jni/rime_jni.cc` | 已编入并引用 Lua、Octagram；librime 源码版本 1.14.0 | 核心依赖已有；仍要验证 Android 编译数据、首次部署、内存和长输入，不把 Windows 测试冒充 Android 测试 |
| Android `DefaultSchemaInstaller.kt` | 只迁移早期朙月默认列表，不会自动迁移当前雾凇列表 | 加入精确识别旧官方默认配置的迁移，先备份；自定义方案列表保持原样 |
| Android `AiKeyboardController.syncScript()` | 固定写入 `traditionalization` | 新方案继续提供同名开关，避免本地候选和 AI 字形不一致 |
| Windows `scripts/prepare-data.py` | 从 Android assets 生成 Windows 数据 | 两端统一引用固定版本资源；避免手工维护两份词典 |
| Windows `data/default.yaml` | 默认 `rime_ai_simp` | 新安装默认万象；升级还要处理用户已有的方案列表和上次选择，不能只改共享文件 |
| Windows `RimeWithWeasel/OrangeCellHandler.inc` | 前端维护输入串，用 `set_input` 刷新，原生 `select_candidate` 分段选择 | 保留此交互和 AI 候选机制；对数字、空格、Shift、回车、撤销逐项回归 |

Windows 目前不是把所有按键原样交给 Rime，所以把完整上游 schema 放进去，并不会自动获得它所有 Lua 快捷键。上游带调词库也不能只替换 `dictionary:` 一行：必须配套转写，才能把 `nǐ/hǎo` 等编码对应到用户输入的 `ni/hao`。

万象 Base 的字母表含数字，数字又可用于声调；我们的 Windows 顶部数字用于选词，Android 数字用于混合输入。首版适配保持现有约定，不启用数字声调输入。中英切换、英文模式输入界面、空格分词、回车输出原文、繁简按钮、长按空格移动光标和在线 AI 行继续由 OrangeCell 管理。日期、计算器、输入统计、额外上下文学习和辅助码等 Lua 功能不默认引入。[Base 配置](https://github.com/amzxyz/rime-wanxiang/blob/v18.1.13/wanxiang.schema.yaml)。

## 5. 建议的正式落地方案

### 默认方案

1. 用 `orangecell_wanxiang` 作为新方案 ID，显示“万象拼音”，默认简体、全拼、简拼和经过回归的错序规则。
2. 采用 Base 核心七份词表和对应的转写，不把所有上游 Lua 和主题整体打包。未来可以在同一数据体系上加双拼。
3. 两端共用一个资源清单，固定上游版本、来源、SHA256、许可和改动记录。建议资源源头放 `shared/rime/`，由构建步骤分别生成 Android assets 和 Windows data。
4. 保留雾凇供切换。两个方案使用独立学习词库，保留旧 `*.userdb` 和自定义短语；不要直接把雾凇二进制学习库改名成万象库，因为编码不同。
5. 新安装直接默认万象；升级只迁移项目生成且未改动的旧默认列表。用户自己配置过的方案不覆盖。迁移失败能回到雾凇。

### 可选本地整句增强

设置项建议名为“本地整句模型”，明确它与在线 AI Policy 不同。默认先关闭，用户可下载或导入已校验的简体 `.gram` 文件后启用。文件缺失、下载中断或校验不符时维持无模型方案，不能影响正常打字。

模型宜独立分发，下载使用临时文件、校验后原子替换；Windows 在更新时先释放 Rime 对文件的映射，再重新部署。Android 不宜每次 APK 更新都重复携带和解压约 407 MB 模型。简体词库转繁体输出可以继续经 OpenCC 完成，不需要因此默认再下载另一个繁体模型。

`.gram` 超过 GitHub 普通 Git 的单文件 100 MiB 限制，应放 Release 资产或独立模型下载地址，仓库保留固定清单和许可证；最终 APK/Setup 大小需要实际打包确认。[GitHub 大文件说明](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)。

### 与在线 AI 的关系

万象负责即时离线候选，现有 OpenAI / OpenRouter / Gemini 继续负责复杂纠错与中英语义处理。无需为了换词库改当前提示词、API 参数或 Preset。

**换词库本身不会自动减少 API 费用。** 当前逻辑满足触发条件就会请求 AI；即使本地候选更准确，请求仍可能已经发出。若后续要利用更好的离线候选省 token，需要另外实现手动 AI、延长触发等待或其他明确的请求策略；不能拿本轮词库替换的预期当成已经实现的省费效果。

### 设为正式默认前的验收

- Android 模拟器：全新安装、当前版本升级、首次部署、重启；字母键盘和数字混输；空格分词；中英/繁简切换；长按空格；选短词后剩余拼音和 AI 候选都保留。
- Windows：逐字输入和退格、数字选词、Shift 中英切换、繁简快捷键、回车原文、候选点击与连续分段选择；记事本和 VS Code 焦点与提交检查。
- 对照本次 60 条和现有长输入回归，单独检查正确拼音退步；保留雾凇结果作为基线。大量生成语料只做本地评估，不发云端。
- 测试长输入每次按键延迟和内存，尤其 Android，优化全拼转写产生的额外分支。Grammar 的增益、代价和典型退步分开统计，不能用某几个好例子替代整体评估。
- 安装包验收包含词典摘要、模型有无两种状态、许可、配置迁移和回退；完成这些后才能宣称正式默认接入完成。

## 6. 许可与来源

万象方案仓库当前根许可证为 **CC BY 4.0**，数据仓库明确将原创词库、拼音数据和文档纳入同一许可。该许可允许复制、修改和再分发，需要保留署名、许可证链接及修改说明；OrangeCell 自身的 GPL 授权不替代这些数据的许可。[方案许可证](https://github.com/amzxyz/rime-wanxiang/blob/wanxiang/LICENSE)、[数据授权范围](https://github.com/amzxyz/rime-wanxiang-data/blob/wanxiang/LICENSE-SCOPE.md)、[CC BY 4.0 条款摘要](https://creativecommons.org/licenses/by/4.0/)。

需要区分数据和工具：`rime-wanxiang-data` 的 `LICENSE-SCOPE.md` 明确说明其原创 Python、Kotlin、Shell、PowerShell 等程序代码目前没有独立授予复制、修改、再分发或商业使用许可。因此本方案只采用已授权的数据，不直接复制那里的更新器 App、后台工具或构建脚本。更新下载逻辑由 OrangeCell 自己实现。第三方组件继续按各自许可证处理。[第三方声明](https://github.com/amzxyz/rime-wanxiang-data/blob/wanxiang/NOTICE.md)。

正式打包时附上万象与模型的来源、版本和完整许可证，在 README/关于页署名并注明 OrangeCell 适配了 schema；当前研究下载的发布 ZIP 没有替代这一分发步骤。

## 7. 本次完成状态

- 已完成上游文档、配置、许可、发布资产与本地代码检查。
- 已校验下载摘要，在独立目录部署词典、加载 Grammar，完成四组 Windows 引擎对照及分段选择/字形检查。
- 研究脚本和大型下载保留在本机独立工作目录；小型输入集、候选记录和本报告保存到项目。
- 应用运行代码、默认方案、安装包、已安装客户端均未修改；未运行云端测试；未提交或推送本轮文档。
