// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.rime

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

@Serializable data class WanxiangAsset(val name:String, val url:String, val size:Long, val sha256:String) {
    fun validate() {
        require(sha256.matches(Regex("[0-9a-f]{64}"))) { "GitHub 未提供有效的 SHA-256 校验值" }
        require(size in 1..800_000_000L) { "下载文件大小异常" }
    }
}
@Serializable data class WanxiangRelease(val version:String, val asset:WanxiangAsset)
@Serializable data class WanxiangState(
    val enabled:Boolean=true, val grammar:Boolean=true,
    val dictionary:WanxiangRelease?=null, val model:WanxiangRelease?=null,
    val iceDictionary:WanxiangRelease?=null,
) {
    fun summary():String = "当前 / Selected: ${if(enabled) "万象 / Wanxiang" else "雾凇 / Rime Ice"}\n"+
        "万象词表: ${dictionary?.let { it.version+" / "+it.asset.sha256.take(8) } ?: "未安装"}\n"+
        "雾凇词表: ${iceDictionary?.let { it.version+" / "+it.asset.sha256.take(8) } ?: "内置"}\n"+
        "万象语法模型: "+when {
            !enabled -> if(model==null) "未下载 · 当前使用雾凇" else "已下载 · 雾凇模式不启用"
            !grammar -> "已关闭 · 仅词表"
            model==null -> "待下载 · 当前仅用万象词表"
            else -> "已启用 / ON · ${model.asset.sha256.take(12)}"
        }

}
data class WanxiangProgress(val message:String, val done:Long=0, val total:Long=0, val canCancel:Boolean=true)

internal val wanxiangJson=Json { ignoreUnknownKeys=true; prettyPrint=true; encodeDefaults=true }
internal fun digest(file:File):String {
    val hash=MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { stream ->
        val bytes=ByteArray(128*1024)
        while(true) { val n=stream.read(bytes);if(n<0)break;hash.update(bytes,0,n) }
    }
    return hash.digest().joinToString("") { "%02x".format(it) }
}
/** Same-directory rename; a backup also covers platforms without replace-on-rename. */
internal fun writeSafely(file:File, bytes:ByteArray) {
    file.parentFile.mkdirs()
    val temp=File(file.parentFile,file.name+".new")
    val backup=File(file.parentFile,file.name+".bak")
    if(!file.exists() && backup.exists()) check(backup.renameTo(file))
    FileOutputStream(temp).use { it.write(bytes);it.fd.sync() }
    if(backup.exists())check(backup.delete())
    if(file.exists())check(file.renameTo(backup)) { "无法替换 ${file.name}，文件可能正在使用" }
    if(!temp.renameTo(file)) {
        backup.renameTo(file)
        error("无法写入 ${file.name}")
    }
    backup.delete()
}
internal fun writeSafely(file:File, text:String)=writeSafely(file,text.toByteArray(Charsets.UTF_8))

object WanxiangCatalog {
    const val DICTIONARY_API="https://api.github.com/repos/amzxyz/rime-wanxiang/releases/latest"
    const val MODEL_API="https://api.github.com/repos/amzxyz/rime-wanxiang-data/releases/tags/LTS"
    const val ICE_API="https://api.github.com/repos/iDvel/rime-ice/releases/latest"
    fun parse(body:String, model:Boolean, ice:Boolean=false):WanxiangRelease {
        val root=wanxiangJson.parseToJsonElement(body).jsonObject
        require(root["draft"]?.jsonPrimitive?.booleanOrNull != true && root["prerelease"]?.jsonPrimitive?.booleanOrNull != true) { "只使用正式发布的词库资源" }
        val expected=if(ice) "cn_dicts.zip" else if(model) "wanxiang-lts-zh-hans.gram" else "rime-wanxiang-base.zip"
        val repo=if(ice) "iDvel/rime-ice" else "amzxyz/"+if(model) "rime-wanxiang-data" else "rime-wanxiang"
        val asset=root["assets"]!!.jsonArray.map { it.jsonObject }.singleOrNull { it["name"]?.jsonPrimitive?.content==expected }
            ?: error("GitHub 发布中找不到 $expected")
        val url=asset["browser_download_url"]!!.jsonPrimitive.content
        require(url.startsWith("https://github.com/$repo/releases/download/")) { "非官方词库下载地址" }
        val result=WanxiangAsset(expected,url,asset["size"]!!.jsonPrimitive.long,
            asset["digest"]?.jsonPrimitive?.content.orEmpty().removePrefix("sha256:").lowercase())
        result.validate()
        return WanxiangRelease(root["tag_name"]!!.jsonPrimitive.content.take(100),result)
    }
}
