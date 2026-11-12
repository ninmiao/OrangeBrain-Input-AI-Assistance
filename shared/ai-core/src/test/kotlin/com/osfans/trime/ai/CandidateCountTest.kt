package com.osfans.trime.ai
import kotlin.test.*
class CandidateCountTest {
    private fun pack()=PromptPackage.parse(requireNotNull(javaClass.getResource("/default-prompts.json")).readBytes())
    @Test fun legacyCountsCannotRestoreAlternativesOrCompletion() {
        val text = """{"candidates":["甲","乙","丙"],"completion":"续写"}"""
        for(count in 1..5) assertEquals(AiResult(listOf("甲"),""),Protocol.decode(text,true,count))
        assertEquals(listOf("甲"),Protocol.decode(text,false).candidates)
        assertFails { Protocol.decode(text,false,0) };assertFails { Protocol.decode(text,false,6) }
    }
    @Test fun oldPackagesCannotAppendObsoleteRules() {
        val legacy=pack().copy(revision=8,base_prompt="Return five alternatives",completion_on="Add a story",keyboard_language_rules=LanguageRules("OLD ZH","OLD EN"))
        for(count in 1..5) {
            val prompt=legacy.compose("original",true,true,traditional=true,candidateCount=count)
            assertContains(prompt,"一个最可能的结果");assertContains(prompt,"繁体汉字")
            assertFalse(prompt.contains("OLD"));assertFalse(prompt.contains("five alternatives"));assertTrue(prompt.length<300)
        }
    }
    @Test fun exactShortTemplatesUseOnlySelectedLanguageScriptAndStyle() {
        val p=pack()
        val zh=p.compose("original",true,false)
        assertEquals(p.keyboard_language_rules.chinese.replace("【简体/繁体】","简体").replace("【风格】",p.styles.first().instruction),zh)
        assertContains(zh,"空格标注的词组边界");assertContains(zh,"英文保留并纠错")
        val en=p.compose("formal",false,false,traditional=true)
        assertContains(en,"优先按英文纠错");assertContains(en,"统一转成英文");assertContains(en,"简洁正式")
        assertFalse(en.contains("转为繁体汉字"));assertFalse(en.contains("英文保留"));assertTrue(en.length<300)
        assertContains(p.compose("custom",true,false,"自然温和"),"按自然温和给出")
    }
}
