package com.osfans.trime.ai
import kotlin.test.*
class BenchmarkTest {
 @Test fun selectsOneToFiveExistingPolicies(){val ids=(1..7).map {"p$it"};for(n in 1..5)assertEquals(ids.take(n),PolicyBenchmarks.validate(ids.take(n),ids))}
 @Test fun rejectsUnknownDuplicateEmptyAndOversizedSelection(){for(ids in listOf(emptyList(),listOf("missing"),listOf("one","one"),(1..6).map {"p$it"}))assertFails {PolicyBenchmarks.validate(ids,listOf("one")+(1..6).map {"p$it"})}}
 @Test fun fewerPoliciesNeedNoInventedApiOrModel(){assertEquals(listOf("one"),PolicyBenchmarks.validate(listOf("one"),listOf("one")))}
}
