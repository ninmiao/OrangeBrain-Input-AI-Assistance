// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.rime.android

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.osfans.trime.R
import com.osfans.trime.data.base.DataManager
import com.osfans.trime.daemon.RimeDaemon
import com.osfans.trime.rime.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow

object AndroidWanxiangActivator:WanxiangActivator {
    override suspend fun activate(schema:String) {
        val session=RimeDaemon.createSession("wanxiang-deployer")
        try {
            session.runOnReady {
                clearComposition()
                val selected=(listOf(schema)+selectedSchemata().map { it.id }+WanxiangUpdater.FALLBACK).distinct()
                    .filter { it!=WanxiangUpdater.SCHEMA || java.io.File(DataManager.userDataDir,"$it.schema.yaml").isFile }
                check(setEnabledSchemata(selected.toTypedArray())) { "无法保存 Rime 方案列表" }
                deploy()
                check(selectSchema(schema)) { "无法启用 $schema" }
                val ascii=getRuntimeOption("ascii_mode")
                setRuntimeOption("ascii_mode",false)
                for(c in "nihao")processKey(c.code)
                val candidates=getCandidates(0,5)
                clearComposition();setRuntimeOption("ascii_mode",ascii)
                check(candidates.isNotEmpty()) { "新词库未产生候选，部署验证失败" }
            }
        } finally { RimeDaemon.destroySession("wanxiang-deployer") }
    }
}

data class DownloadState(val busy:Boolean=false,val progress:WanxiangProgress=WanxiangProgress(""))
class WanxiangDownloadService:Service() {
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
    private var job:Job?=null
    override fun onBind(intent:Intent?):IBinder?=null
    override fun onCreate() {
        super.onCreate()
        if(Build.VERSION.SDK_INT>=26)getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL,"词库与模型下载",NotificationManager.IMPORTANCE_LOW))
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if(intent?.action=="cancel") { if(state.value.progress.canCancel)job?.cancel();return START_NOT_STICKY }
        startForeground(ID,notification(WanxiangProgress("准备下载 / Preparing…")))
        if(job?.isActive==true)return START_NOT_STICKY
        state.value=DownloadState(true,WanxiangProgress("准备下载 / Preparing…"))
        job=scope.launch {
            try {
                val updater=WanxiangUpdater(DataManager.userDataDir,AndroidWanxiangActivator,bundledDirectory=DataManager.sharedDataDir,progress={ p ->
                    state.value=DownloadState(true,p)
                    getSystemService(NotificationManager::class.java).notify(ID,notification(p))
                })
                when(intent?.action) {
                    "select" -> updater.selectDictionary(intent.getBooleanExtra("wanxiang",true),intent.getBooleanExtra("grammar",true))
                    "ice" -> updater.updateDictionary(false)
                    "model" -> updater.updateModel()
                    "fallback" -> updater.useFallback()
                    else -> updater.updateDictionary(true)
                }
            } catch(_:CancellationException) {
                state.value=DownloadState(false,WanxiangProgress("已暂停；点击下载可继续 / Paused; click to resume"))
            } catch(error:Exception) {
                state.value=DownloadState(false,WanxiangProgress("${error.message}\n点击下载可重试 / Click to retry"))
            } finally {
                state.value=state.value.copy(busy=false)
                if(Build.VERSION.SDK_INT>=24)stopForeground(STOP_FOREGROUND_REMOVE)
                else @Suppress("DEPRECATION") stopForeground(true)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }
    private fun notification(p:WanxiangProgress):Notification {
        val open=PendingIntent.getActivity(this,0,Intent(this,WanxiangActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop=PendingIntent.getService(this,1,Intent(this,WanxiangDownloadService::class.java).setAction("cancel"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this,CHANNEL).setSmallIcon(R.drawable.ic_baseline_sync_24)
            .setContentTitle("OrangeCell · 词库与模型").setContentText(p.message).setContentIntent(open).setOnlyAlertOnce(true).setOngoing(true)
            .setProgress(100,if(p.total>0)(p.done*100/p.total).toInt() else 0,p.total==0L)
            .apply { if(p.canCancel)addAction(0,"暂停 / Pause",stop) }.build()
    }
    override fun onDestroy() { scope.cancel();super.onDestroy() }
    override fun onTimeout(startId:Int,fgsType:Int) { job?.cancel();stopSelf() }
    companion object {
        private const val CHANNEL="wanxiang-download"
        private const val ID=4207
        val state=MutableStateFlow(DownloadState())
    }
}

class WanxiangActivity:AppCompatActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        title="词库与语法模型"
        val dp=resources.displayMetrics.density
        val page=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding((20*dp).toInt(),0,(20*dp).toInt(),0)}
        val scroll=ScrollView(this).apply {addView(page)};setContentView(scroll)
        ViewCompat.setOnApplyWindowInsetsListener(scroll) {v,insets ->
            val bars=insets.getInsets(WindowInsetsCompat.Type.systemBars());v.setPadding(bars.left,bars.top,bars.right,bars.bottom);insets
        }
        fun label(value:String,size:Float=15f)=TextView(this).apply {text=value;textSize=size;setPadding(0,(7*dp).toInt(),0,(7*dp).toInt());page.addView(this)}
        fun button(value:String)=Button(this).apply {text=value;isAllCaps=false;page.addView(this)}
        label("词库与语法模型",24f)
        label("万象、雾凇词表均已内置，离线可切换；各自从官方 GitHub 更新。")
        label("词表与语法模型配合使用。万象模型下载后增强排序；切换雾凇时停用，切回万象后恢复开关。")
        val choice=Spinner(this).apply {adapter=ArrayAdapter(this@WanxiangActivity,android.R.layout.simple_spinner_dropdown_item,arrayOf("万象拼音 / Wanxiang","雾凇拼音 / Rime Ice"));contentDescription="选择词库";page.addView(this)}
        val grammar=Switch(this).apply {text="万象语法模型（默认开启，下载后生效）";isChecked=true;contentDescription="万象语法模型开关";page.addView(this)}
        val apply=button("重新部署当前词库")
        val wanxiang=button("更新万象词表")
        val ice=button("更新雾凇词表")
        val model=button("下载 / 更新万象语法模型")
        label("模型约 407 MB，不内置安装包；模型按钮才下载它。支持暂停续传，首次部署需几分钟。建议 Wi-Fi，预留 1.5 GB 空间。")
        val cancel=button("暂停下载 / Pause").apply {isEnabled=false}
        val bar=ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal).apply {max=100;page.addView(this,LinearLayout.LayoutParams(-1,(12*dp).toInt()))}
        val info=label("读取状态…")
        label("万象：amzxyz · CC BY 4.0；雾凇：iDvel · GPL-3.0-only。词表和模型均在本地使用，云端 AI 独立配置。")
        var busy=false
        var applied:Pair<Boolean,Boolean>?=null
        fun begin(action:String) {
            val intent=Intent(this,WanxiangDownloadService::class.java).setAction(action).putExtra("grammar",grammar.isChecked).putExtra("wanxiang",choice.selectedItemPosition==0)
            ContextCompat.startForegroundService(this,intent)
        }
        fun autoApply() {val desired=(choice.selectedItemPosition==0) to grammar.isChecked;if(!busy && applied!=null && applied!=desired){applied=desired;begin("select")}}

        fun controls() {choice.isEnabled=!busy;grammar.isEnabled=!busy && choice.selectedItemPosition==0;model.isEnabled=grammar.isEnabled
            listOf(apply,wanxiang,ice).forEach {it.isEnabled=!busy} }
        choice.onItemSelectedListener=object:AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent:AdapterView<*>?) {}
            override fun onItemSelected(parent:AdapterView<*>?,view:android.view.View?,position:Int,id:Long) {controls();autoApply()}
        }
        grammar.setOnCheckedChangeListener {_,_->autoApply()}
        lifecycleScope.launch {
            runCatching {withContext(Dispatchers.IO) {WanxiangUpdater(DataManager.userDataDir,AndroidWanxiangActivator,bundledDirectory=DataManager.sharedDataDir).state()}}
                .onSuccess {applied=it.enabled to it.grammar;choice.setSelection(if(it.enabled)0 else 1);grammar.isChecked=it.grammar;info.text=it.summary()}.onFailure {info.text="${it.message}"}
            WanxiangDownloadService.state.collect {s ->
                busy=s.busy
                if(!busy && s.progress.message.isNotEmpty()) runCatching {withContext(Dispatchers.IO) {WanxiangUpdater(DataManager.userDataDir,AndroidWanxiangActivator,bundledDirectory=DataManager.sharedDataDir).state()}}
                    .onSuccess {applied=it.enabled to it.grammar;choice.setSelection(if(it.enabled)0 else 1);grammar.isChecked=it.grammar}
                controls()
                if(s.progress.message.isNotEmpty())info.text=s.progress.message+if(s.progress.total>0)"\n${s.progress.done/1_000_000} / ${s.progress.total/1_000_000} MB" else ""
                cancel.isEnabled=s.busy && s.progress.canCancel
                bar.isIndeterminate=s.busy && s.progress.total==0L
                if(s.progress.total>0)bar.progress=(s.progress.done*100/s.progress.total).toInt()
            }
        }
        apply.setOnClickListener {begin("select")};wanxiang.setOnClickListener {begin("wanxiang")};ice.setOnClickListener {begin("ice")};model.setOnClickListener {begin("model")}
        cancel.setOnClickListener {startService(Intent(this,WanxiangDownloadService::class.java).setAction("cancel"))}

    }
}
