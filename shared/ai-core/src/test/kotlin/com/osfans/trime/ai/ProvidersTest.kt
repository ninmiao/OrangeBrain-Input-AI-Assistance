package com.osfans.trime.ai
import kotlin.test.*
class ProvidersTest {
 @Test fun endpointTagsNotDisplayNamesAreUsedAndDeduplicated() {
  val list=ProvidersClient.decode("""{"data":{"endpoints":[{"provider_name":"Wafer","tag":"wafer/us"},{"provider_name":"Wafer","tag":"wafer/us"},{"provider_name":"Other","tag":"other/fp8"},{"provider_name":"No ID"}]}}""".toByteArray())
  assertEquals(setOf("wafer/us","other/fp8"),list.map{it.id}.toSet())
  assertTrue(list.any{it.label=="Wafer · wafer/us"})
 }
 @Test fun modelIsEncodedAndOriginCannotBeRedirected() {
  assertEquals("https://openrouter.ai/api/v1/models/deepseek/model%3Afree/endpoints",ProvidersClient.url("deepseek/model:free"))
  assertFails{ProvidersClient.url("../x")};assertFails{ProvidersClient.url("x/ /y")}
  assertFails{ProvidersClient.decode("{}".toByteArray())}
 }
}
