package com.osfans.trime.ai
import kotlin.test.*
class CandidateCountTest {
    @Test fun limitsKeepRankedPrefixAndAllowFewerCandidates() {
        val text = """{"candidates":["甲","乙","丙","丁","戊"],"completion":""}"""
        for (count in 1..5) assertEquals(listOf("甲","乙","丙","丁","戊").take(count), Protocol.decode(text,false,count).candidates)
        assertEquals(3,Protocol.decode(text,false).candidates.size)
        assertEquals(listOf("你好"),Protocol.decode("""{"candidates":["你好"],"completion":""}""",false,5).candidates)
        assertFails { Protocol.decode(text,false,0) }; assertFails { Protocol.decode(text,false,6) }
    }
    @Test fun legacyPoliciesReceiveCountAndKeepLanguageContract() {
        val pack=PromptPackage.parse(requireNotNull(javaClass.getResource("/default-prompts.json")).readBytes())
            .copy(base_prompt="Usually return ONE candidate")
        for(count in 1..5) {
            val prompt=pack.compose("original",true,false,traditional=true,candidateCount=count)
            assertTrue(prompt.contains("Target $count distinct candidates"))
            assertTrue(prompt.substringAfterLast("\n\n").contains("Traditional Chinese"))
        }
        assertFails { pack.compose("original",true,false,candidateCount=0) }
    }
}
