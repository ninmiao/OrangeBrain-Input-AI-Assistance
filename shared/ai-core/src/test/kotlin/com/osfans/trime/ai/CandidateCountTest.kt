package com.osfans.trime.ai
import kotlin.test.*
class CandidateCountTest {
 @Test fun arraysPreserveRankingAndDeduplicate(){ assertEquals(listOf("甲","乙"),Protocol.decode("""["甲","乙","甲"]""").candidates) }
 @Test fun plainTextAndThinkingNeverBecomeCandidates(){ for(t in listOf("你好","<think>分析</think>[\"你好\"]","```json\n[\"你好\"]\n```","[\"<think>分析</think>\"]"))assertFails {Protocol.decode(t)} }
 @Test fun oldPromptMigratesToStructuredContextContract(){ val old=PromptPackage(revision=8,response_schema_version=1,keyboard_language_rules=LanguageRules("OLD","OLD"));assertEquals(PromptPackage().compose(true),old.compose(true)) }
 @Test fun customRuleKeepsMandatoryContract(){val p=PromptPackage(keyboard_language_rules=LanguageRules("CUSTOM ZH","CUSTOM EN"));assertTrue(p.compose(true).startsWith("CUSTOM ZH"));assertTrue(p.compose(false).endsWith(PromptPackage.OUTPUT_RULE))}
}
