// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.app.Dialog
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.text.TextUtils
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.osfans.trime.data.db.ClipboardHelper
import com.osfans.trime.data.prefs.AppPrefs
import com.osfans.trime.ime.core.TrimeInputMethodService
import kotlinx.coroutines.*

/** Read the current system clipboard on demand, including copies made before this IME started. */
internal class KeyboardClipboard(private val service:TrimeInputMethodService,private val scope:CoroutineScope) {
    private var dialog:Dialog?=null
    private fun dp(n:Int)=(n*service.resources.displayMetrics.density).toInt()
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
            val entries=(listOfNotNull(current)+history).filter {it.isNotBlank()}.distinct().take(50)
            val context=ContextThemeWrapper(service,android.R.style.Theme_Material_Light)
            val d=Dialog(context).apply { requestWindowFeature(Window.FEATURE_NO_TITLE) }
            d.setContentView(panel(context,entries,current) { text -> d.dismiss(); if(valid())paste(text) })
            d.window?.apply {
                setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
                setLayout((service.resources.displayMetrics.widthPixels*0.94f).toInt(),ViewGroup.LayoutParams.WRAP_CONTENT)
            }
            dialog=d.also(service::showDialog)
        }
    }

    private fun panel(context:Context,entries:List<String>,current:String?,choose:(String)->Unit):View {
        val root=LinearLayout(context).apply {
            orientation=LinearLayout.VERTICAL;setPadding(dp(16),dp(14),dp(16),dp(12))
            background=GradientDrawable().apply { setColor(Color.WHITE);cornerRadius=dp(22).toFloat() }
        }
        val header=LinearLayout(context).apply { gravity=Gravity.CENTER_VERTICAL }
        header.addView(ClipboardGlyph(context).apply { color=FunctionGlyphView.INDIGO;isClickable=false;background=null;contentDescription=null;importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO },LinearLayout.LayoutParams(dp(26),dp(26)))
        header.addView(TextView(context).apply {
            text="剪贴板";textSize=17f;setTextColor(0xff1f2329.toInt());typeface=Typeface.create("sans-serif-medium",Typeface.BOLD)
            setPadding(dp(8),0,dp(8),0)
        })
        header.addView(TextView(context).apply { text=if(entries.isEmpty())"" else "${entries.size} 条";textSize=12f;setTextColor(0xff8a8f98.toInt()) },
            LinearLayout.LayoutParams(0,-2,1f))
        header.addView(TextView(context).apply {
            text="关闭";textSize=14f;setTextColor(FunctionGlyphView.INDIGO);setPadding(dp(12),dp(6),dp(4),dp(6))
            setOnClickListener { close() }
        })
        root.addView(header)
        if(entries.isEmpty()) {
            root.addView(TextView(context).apply {
                text="剪贴板没有文字，复制后再打开即可。";textSize=14f;setTextColor(0xff8a8f98.toInt());gravity=Gravity.CENTER
                setPadding(0,dp(28),0,dp(28))
            })
            return root
        }
        val list=LinearLayout(context).apply { orientation=LinearLayout.VERTICAL;setPadding(0,dp(6),0,0) }
        entries.forEachIndexed { i,text -> list.addView(item(context,text,i==0 && text==current) { choose(text) }) }
        val itemHeight=dp(50)
        root.addView(ScrollView(context).apply { isVerticalScrollBarEnabled=false;addView(list) },
            LinearLayout.LayoutParams(-1,minOf(entries.size*itemHeight+dp(6),dp(330))))
        return root
    }

    /** One entry on one line: whitespace and line breaks collapse, the end is elided. */
    private fun item(context:Context,text:String,isCurrent:Boolean,onClick:()->Unit):View {
        val shape={ GradientDrawable().apply { setColor(0xfff3f4f7.toInt());cornerRadius=dp(14).toFloat() } }
        return LinearLayout(context).apply {
            gravity=Gravity.CENTER_VERTICAL;setPadding(dp(12),0,dp(12),0)
            background=RippleDrawable(android.content.res.ColorStateList.valueOf(0x24565CC6),shape(),shape())
            isClickable=true;isFocusable=true;setOnClickListener { onClick() }
            contentDescription=(if(isCurrent)"当前复制：" else "历史：")+text.take(200)
            layoutParams=LinearLayout.LayoutParams(-1,dp(44)).apply { topMargin=dp(6) }
            if(isCurrent) addView(TextView(context).apply {
                this.text="当前";textSize=11f;setTextColor(Color.WHITE);setPadding(dp(7),dp(2),dp(7),dp(2))
                background=GradientDrawable().apply { setColor(FunctionGlyphView.INDIGO);cornerRadius=dp(8).toFloat() }
            },LinearLayout.LayoutParams(-2,-2).apply { marginEnd=dp(8) })
            addView(TextView(context).apply {
                this.text=text.replace(Regex("\\s+")," ").trim()
                textSize=15f;setTextColor(0xff1f2329.toInt());isSingleLine=true;ellipsize=TextUtils.TruncateAt.END
            },LinearLayout.LayoutParams(0,-2,1f))
            if(text.length>40) addView(TextView(context).apply {
                this.text="${text.length} 字";textSize=11f;setTextColor(0xff9aa0a8.toInt());setPadding(dp(8),0,0,0)
            })
        }
    }
}
