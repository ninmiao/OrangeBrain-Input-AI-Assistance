package com.osfans.trime.ai
import kotlin.test.*

class StrictPromptMigrationTest {
    @Test fun oldCustomPromptsKeepTheirInstructionsAndAcquireOutputContract() {
        val old=PromptPackage(version="4.0.0",revision=12,keyboard_language_rules=LanguageRules("custom Chinese instruction","custom English instruction"))
        for(chinese in listOf(true,false)) {
            val composed=old.compose(chinese)
            assertTrue(composed.startsWith(if(chinese) "custom Chinese instruction" else "custom English instruction"))
            assertEquals(1,composed.split(PromptPackage.outputRule(chinese)).size-1)
            assertContains(composed,PromptPackage.KAOMOJI_RULE)
        }
        assertEquals(13L,old.upgraded().revision)
    }
    @Test fun alreadyStrictPromptIsNotDuplicated() {
        val p=PromptPackage()
        for(chinese in listOf(true,false))assertEquals(1,p.compose(chinese).split(PromptPackage.outputRule(chinese)).size-1)
    }
}
