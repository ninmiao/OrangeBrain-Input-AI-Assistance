package com.osfans.trime.ai.android
import android.os.Bundle
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.osfans.trime.ai.*
import kotlinx.coroutines.*
/** Benchmark selections contain Policy IDs only; credentials and parameters are resolved at run time. */
class BenchmarkActivity:AppCompatActivity() {
 private lateinit var store:AiStore
 private lateinit var rows:LinearLayout
 private lateinit var output:TextView
 private lateinit var run:Button
 private lateinit var sample:EditText
 private lateinit var before:EditText
 private lateinit var after:EditText
 private lateinit var language:Switch
 private val selected=linkedSetOf<String>()
 private var job:Job?=null
 private val prefs by lazy { getSharedPreferences("benchmark-policy-selection",MODE_PRIVATE) }
 override fun onCreate(state:Bundle?) {
  super.onCreate(state);title="Policy 一键测速"
  lifecycleScope.launch { store=withContext(Dispatchers.IO){AiStore.get(this@BenchmarkActivity)};render() }
 }
 private fun render() {
  val page=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(24,36,24,24)}
  setContentView(ScrollView(this).apply {addView(page)})
  fun label(s:String)=TextView(this).apply {text=s;setPadding(0,12,0,12);page.addView(this)}
  fun input(caption:String,value:String):EditText {label(caption);return EditText(this).apply {setText(value);minLines=2;contentDescription=caption;page.addView(this)}}
  label("选择已有 Policy（1–5 个）").textSize=22f
  label("使用各 Policy 当前的模型、思考、速度、供应商、Key 和提示词。没有五个也可以测速。")
  rows=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL};page.addView(rows)
  val policies=store.config.policies
  val saved=prefs.getStringSet("ids",null)
  selected.addAll(if(saved==null) policies.take(5).map {it.id} else policies.filter {it.id in saved}.map {it.id}.take(5))
  policies.forEach {p -> rows.addView(CheckBox(this).apply {
   text="${p.name}\n${p.model} · ${store.policyParameterSummary(p)}"+if(ApiRouting.isOpenRouter(p.endpoint))" · ${p.provider.ifBlank {"自动路由"}}" else ""
   contentDescription="测速 Policy ${p.name}";isChecked=p.id in selected
   setOnCheckedChangeListener { _,checked ->
    if(checked && selected.size>=5 && p.id !in selected){isChecked=false;Toast.makeText(this@BenchmarkActivity,"最多选择五个 Policy",Toast.LENGTH_SHORT).show()}
    else {if(checked)selected.add(p.id) else selected.remove(p.id);prefs.edit().putStringSet("ids",selected.toSet()).apply()}
   }
  }) }
  language=Switch(this).apply {text="中文样例（关闭为英文）";isChecked=true};page.addView(language)
  sample=input("当前输入",LatencySamples.chinese)
  before=input("前文样例（按设置截取）",LatencySamples.before(true))
  after=input("后文样例（默认读取 0 字）",LatencySamples.after(true))
  language.setOnCheckedChangeListener {_,zh -> sample.setText(if(zh)LatencySamples.chinese else LatencySamples.english);before.setText(LatencySamples.before(zh));after.setText(LatencySamples.after(zh))}
  run=Button(this).apply {text="测试所选 Policy";setOnClickListener {begin()}};page.addView(run)
  page.addView(Button(this).apply {text="停止";setOnClickListener {job?.cancel()}})
  output=label("")
 }
 private fun begin() {
  if(job?.isActive==true)return
  val snapshot=store.config;val policies=snapshot.policies.filter {it.id in selected}
  if(runCatching {PolicyBenchmarks.validate(selected.toList(),snapshot.policies.map {it.id})}.isFailure){output.text="请选择 1–5 个已有 Policy";return}
  val zh=language.isChecked
  val input=try {Protocol.context(sample.text.toString(),before.text.toString(),after.text.toString(),snapshot.contextEnabled,snapshot.beforeLength,snapshot.afterLength).also {Protocol.encode(it)}} catch(_:Exception){output.text="样例无效：当前输入最多 300 字";return}
  run.isEnabled=false;output.text="测试包含前 ${input.before.codePointCount(0,input.before.length)}、后 ${input.after.codePointCount(0,input.after.length)} 个字符。\n"
  job=lifecycleScope.launch {
   try {policies.forEach {p ->
    ensureActive();val c=p.applyTo(snapshot);val started=android.os.SystemClock.elapsedRealtime()
    output.append("\n${p.name} · ${p.model}…\n")
    try {
     val key=withContext(Dispatchers.IO){store.credentialsFor(c).read(c.endpoint)} ?: error("未配置 Key")
     val request=AiRequest(RequestStamp(0,0,0,0,c.generation),input,store.prompt(c,zh),false,outputTokenBudget=c.outputTokenBudget,assistantEnabled=c.assistantEnabled)
     val result=ChatCompletionsClient().request(c.endpoint,key,c.model,request,c.timeoutMs,store.parameters(c),c.provider)
     output.append("${android.os.SystemClock.elapsedRealtime()-started} ms · ${result.candidates.joinToString(" / ")}\n${result.usage?.summary().orEmpty()}\n")
    }catch(e:CancellationException){throw e}catch(e:Exception){output.append("${android.os.SystemClock.elapsedRealtime()-started} ms · ${AiFailure.from(e).label}\n")}
   }} finally {run.isEnabled=true}
  }
 }
 override fun onStop(){super.onStop();job?.cancel()}
}
