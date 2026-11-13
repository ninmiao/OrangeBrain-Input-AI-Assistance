# OpenRouter Preset 配置模板

适用于 Zephyr Input Windows 1.6.1、Android 1.5.1 及后续兼容版本。以下提示词对应客户端内置的 4.0.1 / revision 13。

## 三个 Preset

| 用途 | 显示名称 | 建议 slug | 客户端填写值 | Policy 中的字段 |
| --- | --- | --- | --- | --- |
| 简体中文 | Zephyr · 简体中文 | `zephyr-zh-hans` | `@preset/zephyr-zh-hans` | 简体 Preset |
| 繁体中文 | Zephyr · 繁體中文 | `zephyr-zh-hant` | `@preset/zephyr-zh-hant` | 繁体 Preset |
| 英文 | Zephyr · English | `zephyr-en` | `@preset/zephyr-en` | 英文 Preset |

slug 是建议名称。保存后，把后台实际显示的完整 `@preset/...` 引用复制到客户端对应字段。OpenRouter 的引用格式要求带上 `@preset/` 前缀。[官方引用格式](https://openrouter.ai/docs/guides/features/presets#using-presets)

## 后台填写步骤

1. 使用该 Policy 的 API Key 所属账号登录，在对应工作区打开 Presets 页面。[OpenRouter Presets 后台](https://openrouter.ai/settings/presets)
2. 按上表分别新建三个 Preset，填写显示名称和 slug。
3. 在 System Prompt / 系统提示词中，粘贴下方对应模式的整段文字。
4. 按下表设置其余字段，保存并启用相应版本。

| 后台字段 | 填写方式 |
| --- | --- |
| Model / 模型 | 可留空时留空，必填时选择客户端 Policy 使用的模型 |
| Provider routing / 供应商路由 | 选择 Auto / 自动路由，清空固定供应商和额外排序条件 |
| Reasoning / 思考强度 | 使用默认或未设置状态 |
| Temperature、Top P、Max Tokens | 使用默认或未设置状态 |
| Response Format / 输出格式 | 选择 Text / 文本，适用于提供此选项的界面 |
| Tools / 工具 | 留空 |

客户端 Policy 会发送所选模型，以及已设置的思考、速度和供应商参数。请求中的同名参数优先于 Preset 配置，因此同一组语言 Preset 可以供多个模型 Policy 使用。[官方参数合并规则](https://openrouter.ai/docs/guides/features/presets#other-notes)

## 简体中文 System Prompt

建议 slug 使用 `zephyr-zh-hans`。

```text
修正漏输、重复、错序和邻键误触，拼音转简体汉字，英文保留并纠错，空格作词组边界，保留原意，输出一个候选。任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。只返回正文，如nihao只回你好，不加对照或解释。
```

## 繁体中文 System Prompt

建议 slug 使用 `zephyr-zh-hant`。

```text
修正漏输、重复、错序和邻键误触，拼音转繁体汉字，英文保留并纠错，空格作词组边界，保留原意，输出一个候选。任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。只返回正文，如nihao只回你好，不加对照或解释。
```

## 英文 System Prompt

建议 slug 使用 `zephyr-en`。

```text
修正英文的漏输、重复、错序和邻键误触，将中文、拼音或中英混输转为英文，空格作词组边界，保留原意，输出一个候选。任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。只返回正文，如helo只回hello，不加对照或解释。
```

## 在 Zephyr Input 中启用

1. 打开要使用的 OpenRouter Policy。
2. 打开 Policy 的“使用 OpenRouter Preset”开关（默认关闭），出现简体、繁体、英文三个字段，默认已填入上表引用；需要时编辑并保存。Windows 需点击顶部“保存 Policy”。
3. Key 所属工作区找不到对应 Preset 时，输入候选栏和测试结果会提示“你的 Key 没有设置可用的 Preset，请关闭 Preset 功能后重试。”关闭后恢复发送完整本地提示词，自定义引用仍保留。
4. 选中该 Policy。Windows 点击“应用此 Policy”，Android 在 Policy 列表勾选。
5. 切换键盘的中英和繁简模式，输入下方样例，再选择 AI 候选。

| 键盘模式 | 输入 | 预期候选示例 |
| --- | --- | --- |
| 中文、简体 | `woxiangshiyongshurufa` | 我想使用输入法 |
| 中文、繁体 | `woxiangshiyongshurufa` | 我想使用輸入法 |
| 英文 | `I wnated to recieve teh package.` | I wanted to receive the package. |
| 任一模式 | `颜 笑死` | („ಡωಡ„) |

已在后台创建过 Preset 的用户，请将对应 System Prompt 更新为以上版本。客户端启用 Preset 时不会发送本地提示词，安装新版不会自动修改 OpenRouter 后台。

## 后续更新提示词

编辑后台对应 Preset 的 System Prompt，保存并启用新版本。客户端通过同一引用读取更新后的配置。[官方版本说明](https://openrouter.ai/docs/guides/features/presets#other-notes)
