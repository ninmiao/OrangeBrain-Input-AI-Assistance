package com.osfans.trime.ai
import kotlin.test.*
class LatencySamplesTest {
    @Test fun bothDefaultsAreLongAndWithinCompositionLimit() {
        listOf(LatencySamples.chinese,LatencySamples.english).forEach { assertTrue(it.length in 100..300) }
        assertEquals(LatencySamples.chinese,LatencySamples.input(true).input);assertTrue(LatencySamples.input(true).before.isNotEmpty())
    }
    @Test fun migrationOnlyChangesThePreviousBuiltinDefault() {
        assertEquals(LatencySamples.chinese,LatencySamples.migrate("wojintianyoumeeting"))
        assertEquals("my custom sample",LatencySamples.migrate("my custom sample"))
    }
}
