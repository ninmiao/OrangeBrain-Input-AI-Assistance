package com.osfans.trime.ai
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
@Serializable data class LanguageRules(val chinese:String="",val non_chinese:String="")
@Serializable data class PromptPackage(val schema_version:Int=3,val package_id:String="zephyr-input",val version:String="5.0.0",val revision:Long=14,val response_schema_version:Int=3,val keyboard_language_rules:LanguageRules=LanguageRules()) {
 fun upgraded():PromptPackage=if(revision<14||response_schema_version<3)PromptPackage(package_id=package_id) else this
 fun compose(chinese:Boolean,traditional:Boolean=false,assistantEnabled:Boolean=false):String {
  val rules=upgraded().keyboard_language_rules
  return NativeCore.invoke("prompt",buildJsonObject {put("assistantEnabled",assistantEnabled);put("chinese",chinese);put("traditional",traditional);put("custom",if(chinese)rules.chinese else rules.non_chinese)}).jsonPrimitive.content
 }
 companion object {
  const val KAOMOJI_RULE="任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。"
  const val OUTPUT_RULE="仅输出JSON字符串数组，如[\"你好\"]，按可能性排序，默认一个完整候选；不输出思考、解释或代码块。"
  const val ENGLISH_OUTPUT_RULE=OUTPUT_RULE
  fun outputRule(chinese:Boolean)=OUTPUT_RULE
  fun parse(bytes:ByteArray):PromptPackage {
   require(bytes.size<=128*1024)
   return Json { ignoreUnknownKeys=true }.decodeFromString<PromptPackage>(bytes.toString(Charsets.UTF_8)).also {
    require(it.schema_version in 1..3 && it.response_schema_version in 1..3 && it.revision>=0)
    require(it.keyboard_language_rules.chinese.length<=8192 && it.keyboard_language_rules.non_chinese.length<=8192)
   }.upgraded()
  }
 }
}
