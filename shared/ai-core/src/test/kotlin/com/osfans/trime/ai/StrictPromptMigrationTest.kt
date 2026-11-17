package com.osfans.trime.ai
import kotlin.test.*
class StrictPromptMigrationTest {
 @Test fun rawTextRevisionMigrates(){val old=PromptPackage(version="4.0.1",revision=13,keyboard_language_rules=LanguageRules("只返回纯文本","Return plain text"));assertEquals(14L,old.upgraded().revision);assertEquals(PromptPackage().compose(true),old.compose(true))}
 @Test fun formatContractAppearsOnce(){for(zh in listOf(true,false)){val p=PromptPackage();assertEquals(1,p.compose(zh).split(PromptPackage.OUTPUT_RULE).size-1);assertContains(p.compose(zh),PromptPackage.KAOMOJI_RULE)}}
}
