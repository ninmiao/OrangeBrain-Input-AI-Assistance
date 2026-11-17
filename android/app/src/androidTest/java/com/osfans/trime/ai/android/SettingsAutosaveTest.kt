package com.osfans.trime.ai.android
import android.app.Activity
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
class SettingsAutosaveTest {
 private fun all(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {all(v.getChildAt(it))} else emptyList()
 @Test fun budgetEditSavesEvenWhenImmediatelyLeaving(){
  val ins=InstrumentationRegistry.getInstrumentation();val store=AiStore.get(ins.targetContext);val old=store.config
  var activity:Activity?=null
  try {
   activity=ins.startActivitySync(Intent(ins.targetContext,AiSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
   var field:EditText?=null;val deadline=System.currentTimeMillis()+10000
   while(field==null&&System.currentTimeMillis()<deadline){ins.runOnMainSync {field=all(activity!!.window.decorView).filterIsInstance<EditText>().firstOrNull {it.contentDescription?.toString()?.startsWith("输出 token")==true}};if(field==null)Thread.sleep(50)}
   assertNotNull(field)
   ins.runOnMainSync {field!!.setText("384");activity!!.finish()};ins.waitForIdleSync()
   assertEquals(384,store.config.outputTokenBudget)
  } finally {ins.runOnMainSync {activity?.finish()};ins.waitForIdleSync();store.update {old}}
 }
}
