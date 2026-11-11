// SPDX-License-Identifier: GPL-3.0-or-later
package input.zephyr.windows

import com.osfans.trime.ai.*
import com.sun.jna.*
import com.sun.jna.ptr.*
import com.sun.jna.win32.StdCallLibrary
import com.sun.jna.platform.win32.*
import kotlinx.coroutines.runBlocking
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore

object Wire {
    fun hex(s:String)=s.toByteArray(Charsets.UTF_8).joinToString("") { "%02x".format(it.toInt() and 255) }
    fun unhex(s:String):String { require(s.length<=2400 && s.length%2==0);return s.chunked(2).map { it.toInt(16).toByte() }.toByteArray().toString(Charsets.UTF_8) }
    data class Request(val chinese:Boolean,val traditional:Boolean,val input:String)
    fun decode(data:String):Request {
        require(data.length<=2500)
        val fields=data.split('\t');require(fields.size==4 && fields[0]=="Z1" && fields[1] in listOf("zh","en") && fields[2] in listOf("0","1"))
        val raw=unhex(fields[3]);require(raw.length in 1..300 && raw.none { it.isISOControl() })
        return Request(fields[1]=="zh",fields[2]=="1",raw)
    }
    fun response(config:Configuration,result:AiResult?)="Z1\t${if(config.wordSegmentation) 1 else 0}\t${config.debounceMs}\t${if(config.enterOriginal) 1 else 0}\t${if(config.spaceOriginal) 1 else 0}\n"+
        (result?.candidates ?: emptyList()).take(1).joinToString("\n") { hex(it) }
}
class AiService(private val store:ConfigurationStore) {
    suspend fun request(config:Configuration,policy:Policy,raw:Wire.Request):AiResult {
        config.validate()
        val key=store.key(policy.id,policy.endpoint);require(key.isNotBlank()) { "No API key saved for this policy" }
        val request=AiRequest(RequestStamp(0,0,0,0,0),AiInput(raw.input),Prompts.compose(config,policy,raw.chinese,raw.traditional),config.completion,config.candidateCount)
        return ChatCompletionsClient().request(policy.endpoint,key,policy.model,request,config.timeoutMs,policy.parameters(),policy.provider)
    }
    fun handle(bytes:ByteArray):ByteArray {
        val raw=Wire.decode(bytes.toString(Charsets.UTF_8));val config=store.load()
        val result=if(config.enabled && raw.input.isNotBlank()) runCatching { runBlocking { request(config,config.active(),raw) } }
            .onSuccess { runCatching { store.recordRequestStatus("OK") } }
            .onFailure { error -> runCatching { store.recordRequestStatus(if(error is ApiHttpException) "HTTP ${error.status}" else error.javaClass.simpleName) } }.getOrNull() else null
        return Wire.response(config,result).toByteArray(Charsets.UTF_8)
    }
}
private interface CancelApi:StdCallLibrary {
    fun CancelIoEx(handle:WinNT.HANDLE,overlapped:Pointer?):Boolean
    companion object { val api=Native.load("Kernel32",CancelApi::class.java) }
}
private interface SecurityApi:StdCallLibrary {
    fun ConvertStringSecurityDescriptorToSecurityDescriptorW(s:WString,revision:Int,descriptor:PointerByReference,size:IntByReference?):Boolean
    companion object { val api=Native.load("Advapi32",SecurityApi::class.java) }
}
class PipeBroker(private val store:ConfigurationStore) {
    fun run() {
        val k=Kernel32.INSTANCE
        val username=Advapi32Util.getUserName()
        val sid=Advapi32Util.getAccountByName(username).sidString
        val descriptor=PointerByReference()
        check(SecurityApi.api.ConvertStringSecurityDescriptorToSecurityDescriptorW(WString("D:P(A;;GA;;;$sid)"),1,descriptor,null))
        val sa=WinBase.SECURITY_ATTRIBUTES().apply { lpSecurityDescriptor=descriptor.value;bInheritHandle=false;write() }
        val pool=Executors.newFixedThreadPool(4);val slots=Semaphore(4)
        val service=AiService(store)
        val deadlines=java.util.concurrent.ScheduledThreadPoolExecutor(1) { task -> Thread(task,"pipe-deadline").apply { isDaemon=true } }
        try {
            while(true) {
                slots.acquire()
                // Duplex, message framing, reject remote clients. ACL permits current user only.
                val pipe=k.CreateNamedPipe("\\\\.\\pipe\\ZephyrAI-$username",3,4 or 2 or 8,4,32768,4096,10000,sa)
                check(pipe!=WinBase.INVALID_HANDLE_VALUE) { "Cannot create AI pipe: ${k.GetLastError()}" }
                val connected=k.ConnectNamedPipe(pipe,null) || k.GetLastError()==535
                if(!connected) { k.CloseHandle(pipe);slots.release();continue }
                pool.submit {
                    val deadline=deadlines.schedule({ CancelApi.api.CancelIoEx(pipe,null) },70,java.util.concurrent.TimeUnit.SECONDS)
                    try {
                        val input=ByteArray(4096);val read=IntByReference()
                        if(k.ReadFile(pipe,input,input.size,read,null)) {
                            val response=runCatching { service.handle(input.copyOf(read.value)) }.getOrElse { "Z1\t1\t200\n".toByteArray() }
                            val written=IntByReference();k.WriteFile(pipe,response,response.size,written,null)
                            k.FlushFileBuffers(pipe) // Bounded by the connection deadline.
                        }
                    } finally { deadline.cancel(false);k.DisconnectNamedPipe(pipe);k.CloseHandle(pipe);slots.release() }
                }
            }
        } finally { k.LocalFree(descriptor.value);pool.shutdownNow() }
    }
}
