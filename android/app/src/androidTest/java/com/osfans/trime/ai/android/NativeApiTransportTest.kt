package com.osfans.trime.ai.android
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.*
import org.junit.Test
class NativeApiTransportTest {
 @Test fun threeProvidersRoundTripStructuredCandidatesOverTls()=runBlocking {
  val request=AiRequest(RequestStamp(0,0,0,0,0),AiInput("woxianghekafe","午饭后有点困。","接着继续工作。"),PromptPackage().compose(true),false)
  for(path in listOf("/v1/chat/completions","/v1/responses","/v1beta/interactions")) {
   val result=ChatCompletionsClient().request(TestNetwork.baseUrl+path,"emulator-test-key",if(path.endsWith("interactions"))ApiRouting.HYDROGEN else "fixture-model",request,parameters=mapOf("reasoning_effort" to JsonPrimitive("low")))
   assertTrue(result.candidates.single() in listOf("你好，世界","我想喝咖啡"))
  }
 }
}
