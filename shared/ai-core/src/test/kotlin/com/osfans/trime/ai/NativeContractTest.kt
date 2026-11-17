package com.osfans.trime.ai
import kotlin.test.*
import kotlinx.serialization.json.*
import java.io.File
class NativeContractTest {
 @Test fun truncationCorpusThroughJvmBoundary(){
  val corpus=File("../../tests/corpus/truncated-output.jsonl");assertTrue(corpus.isFile)
  var n=0
  corpus.forEachLine { line -> val c=Json.parseToJsonElement(line).jsonObject;val result=runCatching { Protocol.decode(c.getValue("text").jsonPrimitive.content,truncated=c.getValue("truncated").jsonPrimitive.boolean) }
   if(c.getValue("expected").jsonArray.isNotEmpty())assertEquals(c.getValue("expected").jsonArray.map {it.jsonPrimitive.content},result.getOrThrow().candidates,line) else assertTrue(result.isFailure,line)
   n++
  };assertTrue(n>=10)
 }
 @Test fun softBudgetReservesCandidateAndAllProvidersReceiveContext(){
  val r=AiRequest(RequestStamp(1,1,1,1,1),AiInput("a".repeat(100),"previous","next"),PromptPackage().compose(true),false,outputTokenBudget=1)
  for(ep in listOf(ApiRouting.OPENAI,ApiRouting.OPENROUTER,ApiRouting.GEMINI)){
   val p=ChatCompletionsClient().payload("model",r,endpoint=ep)
   val budget=when(ep){ApiRouting.OPENAI->p["max_output_tokens"];ApiRouting.GEMINI->p["generation_config"]!!.jsonObject["max_output_tokens"];else->p["max_tokens"]}!!.jsonPrimitive.int
   assertTrue(budget>=432);assertContains(p.toString(),"previous");assertContains(p.toString(),"next");assertFalse(p.containsKey("preset"))
  }
 }
 @Test fun malformedNativeRequestsNeverEscapeAsNativeCrashes(){for(op in listOf("decode","payload","envelope","modelDefinition","validateCatalog")){assertFails {NativeCore.invoke(op,JsonPrimitive("bad"))}};assertEquals(listOf("正常"),Protocol.decode("""["正常"]""").candidates)}
 @Test fun excessivelyNestedEnvelopeIsRejected(){val body="[".repeat(1000)+"0"+"]".repeat(1000);assertFailsWith<ApiResponseException>{NativeCore.invoke("envelope",buildJsonObject {put("body",body)})}}

}
