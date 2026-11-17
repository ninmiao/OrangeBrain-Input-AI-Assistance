package com.osfans.trime.ai.android
import com.osfans.trime.ai.*
import org.junit.Test
import org.junit.Assert.*
class AiBenchmarkTest {
 @Test fun selectionUsesExistingIdsOnly(){assertEquals(listOf("a","b"),PolicyBenchmarks.validate(listOf("a","b"),listOf("a","b")));assertTrue(runCatching {PolicyBenchmarks.validate(listOf("unknown"),listOf("a"))}.isFailure)}
 @Test fun benchmarkSamplesIncludeBoundedContext(){for(zh in listOf(true,false)){val input=LatencySamples.input(zh,true,50,12);assertTrue(input.input.length>50);assertTrue(input.before.isNotEmpty());assertTrue(input.after.isNotEmpty());assertTrue(input.before.codePointCount(0,input.before.length)<=50)}}
}
