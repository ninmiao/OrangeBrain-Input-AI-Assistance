package com.osfans.trime.ai.android
import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import kotlinx.serialization.json.*
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
/** Migration tests retain the class name so existing device test commands keep working. */
class PlainTextApiTest {
 private fun fixture(block:(AiStore,File,ContextWrapper)->Unit){val base=InstrumentationRegistry.getInstrumentation().targetContext;val folder=File(base.noBackupFilesDir,"native-migration-${UUID.randomUUID()}").apply {mkdirs()};val ctx=object:ContextWrapper(base){override fun getNoBackupFilesDir()=folder};try {block(AiStore(ctx),folder,ctx)}finally{folder.deleteRecursively()}}
 @Test fun contextDefaultsAndGeminiPolicySurviveReload()=fixture {store,folder,ctx ->
  val p=store.config.policies.single {ApiRouting.isGemini(it.endpoint)}
  assertEquals(ApiRouting.HYDROGEN,p.model);assertTrue(store.config.contextEnabled);assertEquals(50,store.config.beforeLength);assertEquals(0,store.config.afterLength)
  store.update {it.copy(beforeLength=72,afterLength=12,outputTokenBudget=96)}
  val loaded=AiStore(ctx);assertEquals(72,loaded.config.beforeLength);assertEquals(12,loaded.config.afterLength);assertEquals(96,loaded.config.outputTokenBudget)
  val serialized=File(folder,"ai-config.json").readText();assertFalse(serialized.contains("presets"));assertFalse(serialized.contains("customStyle"))
 }
 @Test fun legacyPresetFieldsAreIgnoredWithoutLosingPolicies()=fixture {store,folder,ctx ->
  val before=store.config.policies.map {it.id};val file=File(folder,"ai-config.json")
  val obj=Json.parseToJsonElement(file.readText()).jsonObject
  file.writeText(JsonObject(obj+("presets" to buildJsonObject {put("enabled",true);put("chinese","@preset/old")})).toString())
  val loaded=AiStore(ctx);assertEquals(before,loaded.config.policies.map {it.id})
  val c=loaded.configForPolicy("openrouter");val req=AiRequest(RequestStamp(0,0,0,0,0),LatencySamples.input(true),loaded.prompt(c,true),false)
  val p=ChatCompletionsClient().payload(c.model,req,endpoint=c.endpoint)
  assertFalse(p.containsKey("preset"));assertEquals(2,p.getValue("messages").jsonArray.size)
 }
 @Test fun switchingApiClearsOldRouterProvider()=fixture {store,_,_ ->
  store.selectPolicy("openrouter");assertEquals(ApiRouting.WAFER,store.config.provider)
  store.updatePolicyConfig("openrouter"){it.copy(endpoint=ApiRouting.GEMINI,model=ApiRouting.HYDROGEN)}
  assertEquals("",store.config.provider)
  store.saveParameters(ApiRouting.GEMINI,ApiRouting.HYDROGEN,mapOf("reasoning_effort" to JsonPrimitive("low")))
  assertEquals("low",store.parameters()["reasoning_effort"]!!.content)
 }
}
