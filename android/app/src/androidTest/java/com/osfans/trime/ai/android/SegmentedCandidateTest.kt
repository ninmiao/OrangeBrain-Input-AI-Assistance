package com.osfans.trime.ai.android

import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class SegmentedCandidateTest {
    @Test fun selectingPrefixPreservesTheRestOfTheComposition()=runBlocking {
        val store=AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext)
        val old=store.config
        val session=RimeDaemon.createSession("segmented-candidate-test")
        try {
            store.update { it.copy(enabled=false) }
            session.runOnReady {clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
            for(paged in listOf(false,true)) {
                for(ch in "xianzaishurufahouxuanyouenti")session.runOnReady {processKey(ch.code)}
                val candidates=session.runOnReady {getCandidates(0,10)}
                val index=candidates.indexOfFirst {it.text=="现在"}
                assertTrue("Prefix candidate is available",index>=0)
                val selected=session.runOnReady {if(paged)selectPagedCandidate(index) else selectCandidate(index)}
                assertTrue(selected)
                assertTrue(session.run {rawInputCached}.contains("shurufa"))
                assertTrue(session.run {compositionCached.preedit}.orEmpty().startsWith("现在"))
                assertTrue(session.runOnReady {getCandidates(0,5)}.isNotEmpty())
                session.runOnReady {clearComposition()}
            }
        } finally {
            session.runOnReady {clearComposition()};RimeDaemon.destroySession("segmented-candidate-test");store.update {old}
        }
    }
}
