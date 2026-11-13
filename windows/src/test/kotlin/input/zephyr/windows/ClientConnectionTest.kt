package input.zephyr.windows
import com.sun.jna.platform.win32.*
import com.sun.jna.ptr.IntByReference
import kotlinx.coroutines.*
import java.util.UUID
import kotlin.test.*

class ClientConnectionTest {
    @Test fun closingRealNativePipeCancelsItsCloudJob()=runBlocking {
        val k=Kernel32.INSTANCE
        val name="\\\\.\\pipe\\ZephyrDisconnect-"+UUID.randomUUID()
        val server=k.CreateNamedPipe(name,3,4 or 2 or 8,1,1024,1024,1000,null)
        check(server!=WinBase.INVALID_HANDLE_VALUE)
        var client:WinNT.HANDLE?=null
        val entered=CompletableDeferred<Unit>();var released=false
        val work=async(Dispatchers.IO) {
            try {
                check(k.ConnectNamedPipe(server,null)||k.GetLastError()==535)
                check(k.ReadFile(server,ByteArray(1),1,IntByReference(),null))
                whileClientConnected({ k.PeekNamedPipe(server,null,0,null,null,null) }) {
                    entered.complete(Unit)
                    try { delay(30000) } finally { released=true }
                }
            } finally { k.DisconnectNamedPipe(server);k.CloseHandle(server) }
        }
        try {
            client=k.CreateFile(name,WinNT.GENERIC_READ or WinNT.GENERIC_WRITE,0,null,WinNT.OPEN_EXISTING,0,null)
            check(client!=WinBase.INVALID_HANDLE_VALUE)
            check(k.WriteFile(client,byteArrayOf(1),1,IntByReference(),null))
            withTimeout(3000){entered.await()}
            val start=System.nanoTime();k.CloseHandle(client);client=null
            withTimeout(1500){work.join()}
            assertTrue(work.isCancelled);assertTrue(released)
            assertTrue((System.nanoTime()-start)/1_000_000<1500)
        } finally { client?.let { k.CloseHandle(it) };work.cancelAndJoin() }
    }
    @Test fun completedRequestDoesNotLeaveADisconnectWatcher()=runBlocking {
        assertEquals("done",whileClientConnected({true}) { "done" })
    }
}
