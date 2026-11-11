package input.zephyr.windows

import kotlinx.serialization.json.*
import kotlinx.coroutines.runBlocking
import java.nio.file.*

/** Bounded, opt-in live evaluation. Credentials remain in DPAPI, never in reports. */
fun evaluate(args:List<String>,store:ConfigurationStore) {
    require(args.size in 3..4) { "--evaluate corpus.jsonl report.json limit(1..500) [policy-id]" }
    val limit=args[2].toInt();require(limit in 1..500)
    val loaded=store.load();val config=if(args.size==4)loaded.copy(selectedPolicy=args[3]) else loaded;config.validate();val service=AiService(store);val results=mutableListOf<JsonObject>()
    Files.newBufferedReader(Paths.get(args[0])).useLines { lines ->
        lines.filter { it.isNotBlank() }.take(limit).forEach { line ->
            val row=Json.parseToJsonElement(line).jsonObject
            val raw=row.getValue("input").jsonPrimitive.content;val lang=row.getValue("language").jsonPrimitive.content
            val expected=row.getValue("expected").jsonArray.map { it.jsonPrimitive.content }
            val start=System.nanoTime()
            val result=runCatching { runBlocking { service.request(config,config.active(),Wire.Request(lang=="zh",false,raw)) } }
            results+=buildJsonObject {
                put("id",row.getValue("id"));put("category",row.getValue("category"));put("language",lang)
                put("elapsed_ms",(System.nanoTime()-start)/1_000_000)
                val candidates=result.getOrNull()?.candidates ?: emptyList()
                put("success",result.isSuccess);put("top1",candidates.firstOrNull() in expected);put("top3",candidates.take(3).any { it in expected })
                putJsonArray("candidates") { candidates.forEach { add(it) } }
                if(result.isFailure) {
                    val error=result.exceptionOrNull()!!;put("error",error.javaClass.simpleName)
                    if(error is com.osfans.trime.ai.ApiHttpException)put("http_status",error.status)
                }
            }
        }
    }
    val report=buildJsonObject {
        put("timestamp",java.time.Instant.now().toString());put("policy",config.active().id);put("reasoning",config.active().reasoning);put("speed",config.active().speed);put("prompt_revision",Prompts.pack.revision);
        put("kind","live-model-quality");put("model",config.active().model);put("count",results.size)
        put("top1",results.count { it.getValue("top1").jsonPrimitive.boolean });put("top3",results.count { it.getValue("top3").jsonPrimitive.boolean })
        put("results",JsonArray(results))
    }
    Files.writeString(Paths.get(args[1]),Json { prettyPrint=true }.encodeToString(JsonObject.serializer(),report))
    println("Evaluated ${results.size} entries; report saved.")
}
