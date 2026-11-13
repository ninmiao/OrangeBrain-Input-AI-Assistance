package com.osfans.trime.ai
import kotlin.test.*
class CandidateCountTest {
    private fun pack()=PromptPackage.parse(requireNotNull(javaClass.getResourceAsStream("/default-prompts.json")).readBytes())
    @Test fun plainTextAlwaysProducesOneCandidate() {
        for(count in 1..5)assertEquals(AiResult(listOf("甲，乙。")),Protocol.decode("甲，乙。",true,count))
    }
    @Test fun legacyPromptCannotBringBackContextStylesOrJson() {
        val legacy=pack().copy(schema_version=1,response_schema_version=1,revision=8,keyboard_language_rules=LanguageRules("OLD JSON","OLD JSON"))
        assertEquals(pack().compose(true,true),legacy.compose(true,true))
    }
    @Test fun currentOverridesKeepTheirOwnLanguageRules() {
        val custom=pack().copy(keyboard_language_rules=LanguageRules("CUSTOM ZH","CUSTOM EN"))
        assertEquals("CUSTOM ZH"+PromptPackage.KAOMOJI_RULE+PromptPackage.OUTPUT_RULE,custom.compose(true))
        assertEquals("CUSTOM EN"+PromptPackage.KAOMOJI_RULE+PromptPackage.ENGLISH_OUTPUT_RULE,custom.compose(false))
    }
}
