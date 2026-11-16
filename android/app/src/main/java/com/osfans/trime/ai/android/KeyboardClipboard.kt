// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.ClipboardManager
import android.content.Context
import android.view.ContextThemeWrapper
import android.app.AlertDialog
import com.osfans.trime.data.db.ClipboardHelper
import com.osfans.trime.data.prefs.AppPrefs
import com.osfans.trime.ime.core.TrimeInputMethodService
import kotlinx.coroutines.*

/** Read the current system clipboard on demand, including copies made before this IME started. */
internal class KeyboardClipboard(private val service:TrimeInputMethodService,private val scope:CoroutineScope) {
    private var dialog:AlertDialog?=null
    fun close() {dialog?.dismiss();dialog=null}
    fun open(valid:()->Boolean,paste:(String)->Unit) {
        close()
        scope.launch {
            val current=runCatching {
                val clip=(service.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
                if(clip!=null && clip.itemCount>0)clip.getItemAt(0).coerceToText(service)?.toString() else null
            }.getOrNull()
            val history=if(AppPrefs.defaultInstance().clipboard.clipboardLimit.getValue()!=0)withContext(Dispatchers.IO) {
                runCatching {ClipboardHelper.getAll().mapNotNull {it.text}}.getOrDefault(emptyList())
            } else emptyList()
            if(!valid())return@launch
            val entries=(listOfNotNull(current)+history).filter {it.isNotEmpty()}.distinct().take(50)
            val context=ContextThemeWrapper(service,android.R.style.Theme_Material_Light)
            val builder=AlertDialog.Builder(context).setTitle("剪贴板").setNegativeButton("关闭",null)
            if(entries.isEmpty())builder.setMessage("剪贴板没有文字，复制后再打开即可。")
            else builder.setItems(entries.mapIndexed {i,text ->
                (if(i==0 && text==current) "当前复制 · " else "历史 · ")+text.replace('\n',' ').take(100)+(if(text.length>100)"…" else "")
            }.toTypedArray()) {_,index ->if(valid())paste(entries[index])}
            dialog=builder.create().also(service::showDialog)
        }
    }
}
