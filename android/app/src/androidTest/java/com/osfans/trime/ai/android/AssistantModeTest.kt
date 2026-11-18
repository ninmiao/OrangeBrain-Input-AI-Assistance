package com.osfans.trime.ai.android

import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import kotlinx.coroutines.runBlocking
import android.content.Intent
import androidx.test.uiautomator.*

class AssistantModeTest {
 @Test fun modeSwitchIsNextToAiAndPersists() {
  val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
  val store=AiStore.get(ins.targetContext);val old=store.config
  var activity:android.app.Activity?=null
  try {
   store.update{it.copy(assistantEnabled=true,consent=true)}
   activity=ins.startActivitySync(Intent(ins.targetContext,AiSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
   val selector=By.text("自动助手（含纠错）")
   assertTrue(d.wait(Until.hasObject(selector),5000))
   fun awaitMode(value:Boolean) {
    val deadline=System.currentTimeMillis()+5000
    while(store.config.assistantEnabled!=value && System.currentTimeMillis()<deadline) Thread.sleep(50)
    assertEquals(value,store.config.assistantEnabled);d.waitForIdle()
   }
   d.findObject(selector).click();awaitMode(false)
   d.findObject(selector).click();awaitMode(true)
  } finally {ins.runOnMainSync{activity?.finish()};store.update{old}}
 }
 @Test fun dualCandidatesAcrossThreeProviders()=runBlocking {
  for(chinese in listOf(true,false)) for(path in listOf("/v1/chat/completions","/v1/responses","/v1beta/interactions")) {
   val request=AiRequest(RequestStamp(1,1,1,1,1),AiInput("chishenme","午饭时间到了。",""),PromptPackage().compose(chinese,false,true),false,assistantEnabled=true)
   val result=ChatCompletionsClient().request(TestNetwork.baseUrl+path,"emulator-test-key","assistant-test",request)
   assertEquals(if(chinese) listOf("吃什么？","吃碗面吧。") else listOf("What should I eat?","Try a sandwich."),result.candidates)
  }
 }
 @Test fun defaultAndPersistedMode() {
  assertFalse(AiConfig().assistantEnabled)
  val context=InstrumentationRegistry.getInstrumentation().targetContext
  val store=AiStore.get(context);val old=store.config
  try {
   store.update { it.copy(assistantEnabled=false) };assertFalse(AiStore(context).config.assistantEnabled)
   assertTrue(store.prompt(store.config,true).contains("一个完整候选"))
   store.update { it.copy(assistantEnabled=true) };assertTrue(AiStore(context).config.assistantEnabled)
   assertTrue(store.prompt(store.config,true).contains("No requests for more info; Give your best result directly."))
  } finally {store.update {old}}
 }
 @Test fun allProvidersKeepApprovedDualContract() {
  for(chinese in listOf(true,false)) for(endpoint in listOf(ApiRouting.OPENAI,ApiRouting.OPENROUTER,ApiRouting.GEMINI)) {
   val prompt=PromptPackage().compose(chinese,false,true)
   val request=AiRequest(RequestStamp(1,1,1,1,1),LatencySamples.input(chinese,true,50,10),prompt,false,assistantEnabled=true)
   val payload=ChatCompletionsClient().payload("fixture-model",request,endpoint=endpoint).toString()
   assertTrue(payload.contains("No requests for more info; Give your best result directly."))
   assertFalse(payload.contains("默认一个候选"))
   assertTrue(prompt.contains(if(chinese) "Allow mixed Chinese and English" else "Both candidates use English only"))
  }
 }
 @Test fun duplicateAndTruncatedRolesStayOrdered() {
  fun decode(text:String,cut:Boolean=false)=NativeCore.invoke("decode",buildJsonObject {
   put("text",text);put("truncated",cut);put("assistantEnabled",true)
  }).jsonObject.getValue("candidates").jsonArray
  assertEquals(2,decode("[\"same\",\"same\"]").size)
  assertEquals(2,decode("```json\n[\"same\",\"same\"]\n```").size)
  assertEquals("first",decode("[\"first\",\"unfinished",true).single().jsonPrimitive.content)
 }
}
