package com.osfans.trime.ai.android
import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
class NativeCoreAndroidTest {
 @Test fun truncationCorpusOnAndroidJni(){
  val lines=InstrumentationRegistry.getInstrumentation().context.assets.open("truncated-output.jsonl").bufferedReader().use {it.readLines()}
  assertTrue(lines.size>=10)
  lines.forEach {line-> val c=Json.parseToJsonElement(line).jsonObject;val expected=c.getValue("expected").jsonArray.map {it.jsonPrimitive.content}
   val result=runCatching {Protocol.decode(c.getValue("text").jsonPrimitive.content,truncated=c.getValue("truncated").jsonPrimitive.boolean)}
   if(expected.isEmpty())assertTrue(line,result.isFailure) else assertEquals(line,expected,result.getOrThrow().candidates)
  }
 }
 @Test fun allThreeApisUseNativePayloadAndContext(){
  for(endpoint in listOf(ApiRouting.OPENAI,ApiRouting.OPENROUTER,ApiRouting.GEMINI)){
   val request=AiRequest(RequestStamp(1,1,1,1,1),LatencySamples.input(true,true,50,10),PromptPackage().compose(true),false,outputTokenBudget=1)
   val payload=ChatCompletionsClient().payload("fixture-model",request,endpoint=endpoint)
   assertFalse(payload.containsKey("preset"));assertTrue(payload.toString().contains("JSON"));assertTrue(payload.toString().contains("前文"))
   assertTrue(Protocol.encode(request.input).contains("\"b\""));assertTrue(Protocol.encode(request.input).contains("\"a\""))
  }
 }
 @Test fun emojiContextHasNoBrokenSurrogate(){assertEquals("😀".repeat(50),Protocol.context("i","😀".repeat(60),"unused").before);assertEquals("",Protocol.context("i","private","secret",false).before)}
}
