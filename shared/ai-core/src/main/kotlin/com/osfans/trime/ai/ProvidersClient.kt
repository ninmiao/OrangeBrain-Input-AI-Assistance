package com.osfans.trime.ai
import java.net.URI
import java.net.URLEncoder
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
data class ProviderOption(val id:String,val name:String) { val label get()="$name · $id" }
class ProvidersClient {
 companion object {
  fun url(model:String):String {
   require(model.length in 3..256 && model.contains('/') && model.none { it.isWhitespace() || it.isISOControl() })
   val parts=model.split('/');require(parts.all { it.isNotEmpty() && it!="." && it!=".." })
   return "https://openrouter.ai/api/v1/models/"+parts.joinToString("/"){URLEncoder.encode(it,"UTF-8")}+"/endpoints"
  }
  fun decode(bytes:ByteArray):List<ProviderOption> {
   require(bytes.size<=2*1024*1024)
   val rows=Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject.getValue("data").jsonObject.getValue("endpoints").jsonArray
   require(rows.size<=1000)
   return rows.mapNotNull { row ->
    val o=row.jsonObject
    val id=o["tag"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
    if(id.isBlank() || id.length>128 || id.any{it.isWhitespace() || it.isISOControl()})return@mapNotNull null
    ProviderOption(id,o["provider_name"]?.jsonPrimitive?.contentOrNull ?: id)
   }.distinctBy{it.id}.sortedBy{it.name}
  }
 }
 suspend fun fetch(model:String):List<ProviderOption> = withContext(Dispatchers.IO) {
  val c=URI(url(model)).toURL().openConnection() as HttpsURLConnection
  try {
   c.instanceFollowRedirects=false;c.connectTimeout=10000;c.readTimeout=10000
   if(c.responseCode!=200)throw ApiHttpException(c.responseCode)
   val bytes=c.inputStream.use { input ->
    val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(4096)
    while(true){val n=input.read(buffer);if(n<0)break;require(out.size()+n<=2*1024*1024);out.write(buffer,0,n)}
    out.toByteArray()
   }
   decode(bytes)
  } finally {c.disconnect()}
 }
}
