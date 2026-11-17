# 中英文输入错误测试库

运行 `python tests/corpus/generate.py` 生成约数十万条 JSONL；`--chinese-seeds 100000` 可扩大。生成文件不进入 Git。

- 中文种子来自项目已携带的雾凇 `cn_dicts/base.dict.yaml`；保留源词库许可证及上游来源说明，见 `android/app/src/main/assets/shared/licenses`。多音同音输入保留多个参考答案，不把其中一个当作唯一正确答案。
- 英文种子、句型及 `gold.tsv` 为 Zephyr 编写，随项目 GPL-3.0-or-later 分发。模板扩展并不等于同样数量的独立语言现象。
- 类别：干净输入、错键、邻键（含斜向）、漏输、重复、多输、相邻换位、复合错误、边界缺失/多空格。
- 每条记录有来源、种子族、确定性划分及可重放的编辑操作。同一种子的所有变体属于同一划分，防止评估泄漏。
- `gold.tsv` 是重点回归参考集。`reviewed=false` 的自动变体不是人工标注质量保证，短拼音存在歧义，英文参考句也可能存在其他正确表达。

运行 `python -m unittest discover -s tests/corpus -p test_corpus.py` 校验全部生成记录的编辑重放、长度、哈希和划分。

真实 API 质量评估：先在 Windows 设置中保存密钥，再用 `ZephyrSettings.exe --evaluate gold.jsonl report.json 60`。最多 500 条/次，显式指定数量。报告 top-1/top-3、错误、逐条延迟；网络/协议通过不代表模型纠错通过。普通本地测试不会调用付费 API。

## 长输入与数据保留

`gold.tsv` 共 60 条，中英文各 30 条。其中新增 16 条输入超过 50 字符的长句，中英文各 8 条，覆盖拼音长句、英文漏输、错序、重复、数字与否定保留。

生成语料保留在 `generated/`，开发清理时保留该目录。已有输出默认拒绝覆盖，需要另存时用 `--output` 指定新目录，明确替换时用 `--overwrite`。生成完成后的 `manifest.json` 记录语料数量与 SHA256。

## 截断响应回归

`truncated-output.jsonl` 单独保存 24 个结构化输出案例，其中 18 个明确截断。覆盖闭合候选、第二候选截断、转义、Unicode、emoji、空响应、思考文本与代码块。`expected: []` 表示应拒绝该响应，不能上屏。原生核心、JVM 桥接与 Android JNI 共享此数据集；它不替代原有拼写语料。
