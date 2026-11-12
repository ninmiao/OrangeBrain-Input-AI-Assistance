package com.osfans.trime.ai.android
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
class LiveProviderTest {
 @Test fun currentModelProvidersLoadWithoutApiKey()=runBlocking {
  val options=ProvidersClient().fetch(ApiRouting.DEEPSEEK)
  assertTrue(options.isNotEmpty());assertTrue(options.any{it.id=="wafer/us"})
  assertEquals(options.size,options.map{it.id}.distinct().size)
 }
}