package input.zephyr.windows
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.*

class OpenRouterLongInputLiveTest {
    @Test fun longPresetInputsUseTheRealJvmTransport()=runBlocking {
        org.junit.jupiter.api.Assumptions.assumeTrue(System.getenv("ZEPHYR_LIVE_LONG_ROUTER")=="1")
        val store=ConfigurationStore();val config=store.load()
        val p=config.policies.first { ApiRouting.isOpenRouter(it.endpoint) }
        val key=store.key(p.id,p.endpoint)
        val models=listOf(p.model,"deepseek/deepseek-v4.1-flash")
        for(model in models) {
            val start=System.nanoTime()
            val result=try { ChatCompletionsClient().request(p.endpoint,key,model,
                AiRequest(RequestStamp(0,0,0,0,0),AiInput(LatencySamples.chinese),Prompts.compose(config,p,true,false),false),
                10000,mapOf("reasoning_effort" to JsonPrimitive("none"),"service_tier" to JsonPrimitive("default")),
                if(model==p.model)p.provider else "","@preset/zephyr-zh-hans")
            } catch(e:Exception) {
                println("LONG ROUTER model=$model chars=${LatencySamples.chinese.length} error=${e.javaClass.simpleName} phase=${(e as? ApiTimeoutException)?.phase}");throw e
            }
            assertEquals(1,result.candidates.size);assertTrue(result.candidates.single().isNotBlank())
            println("LONG ROUTER model=$model chars=${LatencySamples.chinese.length} ms=${(System.nanoTime()-start)/1_000_000} ${result.usage?.summary()}")
        }
    }
}
