package com.osfans.trime.ai.android
import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import org.junit.Assert.*
import org.junit.Test
class KaomojiPromptTest {
 @Test fun packagedRulesAndSavedPolicyUpgrade() {
  val pack=AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext).builtin
  assertEquals(10L,pack.revision)
  for (chinese in listOf(true,false)) {
   val prompt=pack.compose("original",chinese,false)
   assertEquals(1,prompt.split(PromptPackage.KAOMOJI_RULE).size-1)
   val old=pack.copy(revision=9,keyboard_language_rules=LanguageRules("CUSTOM ZH","CUSTOM EN"))
   assertTrue(old.compose("original",chinese,false).startsWith("CUSTOM"))
   assertTrue(old.compose("original",chinese,false).endsWith(PromptPackage.KAOMOJI_RULE))
  }
 }
}
