package com.osfans.trime.ai
import kotlinx.serialization.json.*
/** JNI boundary only. All provider payloads, prompts and candidate parsing live in native-core. */
object NativeCore {
    init {
        if(System.getProperty("java.vm.name").contains("Dalvik")) System.loadLibrary("zephyr_core")
        else {
            val explicit=System.getProperty("zephyr.native.path")
            if(explicit!=null) System.load(explicit) else {
                val file=java.io.File.createTempFile("zephyr-core-", ".dll").apply { deleteOnExit() }
                requireNotNull(javaClass.getResourceAsStream("/native/zephyr_core.dll")) { "Native backend missing" }.use { input -> file.outputStream().use { input.copyTo(it) } }
                System.load(file.absolutePath)
            }
        }
    }
    private external fun call(command:String):String
    fun invoke(op:String,args:JsonElement=JsonObject(emptyMap())):JsonElement {
        val result=Json.parseToJsonElement(call(buildJsonObject { put("op",op);put("args",args) }.toString())).jsonObject
        when(result["error"]?.jsonPrimitive?.content) {
            "truncated" -> throw ApiTruncatedException()
            "provider" -> throw ApiProviderException(result["status"]?.jsonPrimitive?.intOrNull?.takeIf { it>0 })
            "response" -> throw ApiResponseException()
            "invalid" -> throw IllegalArgumentException("Invalid configuration or input")
        }
        return result.getValue("ok")
    }
}
