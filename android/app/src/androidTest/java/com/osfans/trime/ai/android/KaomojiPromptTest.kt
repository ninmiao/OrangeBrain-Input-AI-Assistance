package com.osfans.trime.ai.android
import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import org.junit.Assert.*
import org.junit.Test
class KaomojiPromptTest {
 @Test fun packagedRulesAndSavedPolicyUpgrade() {
  val pack=AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext).builtin
  assertEquals(14L,pack.revision)
  for (chinese in listOf(true,false)) {
   val prompt=pack.compose(chinese)
   assertEquals(1,prompt.split(PromptPackage.KAOMOJI_RULE).size-1)
   val old=pack.copy(revision=9,keyboard_language_rules=LanguageRules("CUSTOM ZH","CUSTOM EN"))
   assertEquals(pack.compose(chinese),old.compose(chinese))
   assertTrue(old.compose(chinese).contains(PromptPackage.KAOMOJI_RULE))
   assertTrue(old.compose(chinese).endsWith(PromptPackage.outputRule(chinese)))
  }
 }
}
