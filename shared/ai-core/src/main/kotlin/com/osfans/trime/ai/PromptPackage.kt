// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable
data class LanguageRules(
    val chinese: String = "修正漏输、重复、错序和邻键误触，拼音转【简体/繁体】汉字，英文保留并纠错，空格作词组边界，保留原意，输出一个候选。任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。只返回正文，如nihao只回你好，不加对照或解释。",
    val non_chinese: String = "修正英文的漏输、重复、错序和邻键误触，将中文、拼音或中英混输转为英文，空格作词组边界，保留原意，输出一个候选。任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。只返回正文，如helo只回hello，不加对照或解释。",
)

@Serializable
data class PromptPackage(
    val schema_version: Int = 2,
    val package_id: String = "zephyr-input",
    val version: String = "4.0.1",
    val revision: Long = 13,
    val response_schema_version: Int = 2,
    val keyboard_language_rules: LanguageRules = LanguageRules(),
) {
    // Old packages required JSON output, context and styles. Upgrade their contract together.
    fun upgraded(): PromptPackage = if (schema_version < 2 || response_schema_version < 2 || revision < 12)
        PromptPackage(package_id = package_id) else if(revision < 13) copy(version="4.0.1",revision=13) else this

    fun compose(chinese: Boolean, traditional: Boolean = false): String {
        val rules = upgraded().keyboard_language_rules
        val selected = (if (chinese) rules.chinese else rules.non_chinese).replace("如“颜 笑死”→", "如“颜 笑死”生成")
        val withKaomoji=if(selected.contains(KAOMOJI_RULE)) selected else selected + KAOMOJI_RULE
        val outputRule=outputRule(chinese)
        return (withKaomoji.replace(OUTPUT_RULE, "").replace(ENGLISH_OUTPUT_RULE, "") + outputRule)
            .replace("【简体/繁体】", if (traditional) "繁体" else "简体")
    }

    companion object {
        const val OUTPUT_RULE = "只返回正文，如nihao只回你好，不加对照或解释。"
        const val ENGLISH_OUTPUT_RULE = "只返回正文，如helo只回hello，不加对照或解释。"
        fun outputRule(chinese:Boolean)=if(chinese) OUTPUT_RULE else ENGLISH_OUTPUT_RULE
        const val KAOMOJI_RULE = "任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。"
        private val json = Json { ignoreUnknownKeys = true }
        fun parse(bytes: ByteArray): PromptPackage {
            require(bytes.size <= 128 * 1024) { "Package too large" }
            val obj = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)) as? JsonObject ?: error("Expected object")
            obj["keyboard_language_rules"]?.let {
                require((it as? JsonObject)?.keys == setOf("chinese", "non_chinese"))
            }
            val pack = json.decodeFromString<PromptPackage>(bytes.toString(Charsets.UTF_8))
            require(pack.schema_version in 1..2 && pack.response_schema_version in 1..2 && pack.revision >= 0)
            val fields = listOf(pack.package_id, pack.version, pack.keyboard_language_rules.chinese, pack.keyboard_language_rules.non_chinese)
            require(fields.all { it.isNotBlank() && it.length <= 16384 })
            return pack.upgraded()
        }
    }
}
