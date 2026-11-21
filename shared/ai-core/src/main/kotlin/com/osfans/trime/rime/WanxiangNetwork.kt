// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.rime

import kotlinx.coroutines.*
import okhttp3.*
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit

/** No API credential is used or sent to GitHub. Public, digest-pinned release assets only. */
class WanxiangNetwork internal constructor(
    private val client:OkHttpClient,
    private val allowTestHttp:Boolean=false,
) {
    constructor():this(OkHttpClient.Builder().connectTimeout(20,TimeUnit.SECONDS)
        .readTimeout(60,TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build())

    private fun allowed(url:HttpUrl):Boolean = (allowTestHttp && url.host in setOf("localhost","127.0.0.1")) ||
        (url.isHttps && (url.host=="github.com" || url.host=="api.github.com" ||
            url.host=="objects.githubusercontent.com" || url.host=="release-assets.githubusercontent.com" ||
            url.host=="github-releases.githubusercontent.com"))

    private suspend fun <T> request(url:String, offset:Long=0, consume:suspend (Response)->T):T=coroutineScope {
        var next=Request.Builder().url(url).header("User-Agent","OrangeCell-Wanxiang")
            .header("Accept-Encoding","identity").apply { if(offset>0)header("Range","bytes=$offset-") }.build()
        repeat(6) {
            require(allowed(next.url)) { "不允许的下载地址" }
            val call=client.newCall(next)
            val cancellation=launch { try { awaitCancellation() } finally { call.cancel() } }
            try {
                val response=withContext(Dispatchers.IO) { call.execute() }
                response.use {
                    if(it.code in setOf(301,302,303,307,308)) {
                        val target=it.header("Location")?.let(next.url::resolve) ?: error("下载重定向地址无效")
                        next=next.newBuilder().url(target).build()
                    } else return@coroutineScope consume(it)
                }
            } finally { cancellation.cancelAndJoin() }
        }
        error("下载重定向次数过多")
    }

    suspend fun iceRelease():WanxiangRelease=metadata(WanxiangCatalog.ICE_API,false,true)
    suspend fun release(model:Boolean):WanxiangRelease=metadata(if(model)WanxiangCatalog.MODEL_API else WanxiangCatalog.DICTIONARY_API,model,false)
    private suspend fun metadata(url:String,model:Boolean,ice:Boolean):WanxiangRelease=request(url) { response ->
        checkStatus(response)
        val bytes=response.body!!.byteStream().use { input ->
            val output=java.io.ByteArrayOutputStream();val buf=ByteArray(8192)
            while(true) { val n=input.read(buf);if(n<0)break;require(output.size()+n<=2_000_000) { "发布信息过大" };output.write(buf,0,n) }
            output.toByteArray()
        }
        WanxiangCatalog.parse(bytes.toString(Charsets.UTF_8),model,ice)
    }
    private fun checkStatus(response:Response) {
        if(response.code==403 || response.code==429)error("GitHub 访问限流，请稍后重试（HTTP ${response.code}）")
        if(!response.isSuccessful)throw IOException("GitHub 下载失败（HTTP ${response.code}），可稍后继续")
    }

    suspend fun download(asset:WanxiangAsset, folder:File, progress:(WanxiangProgress)->Unit):File=withContext(Dispatchers.IO) {
        asset.validate();folder.mkdirs()
        val complete=File(folder,asset.sha256+".download")
        if(complete.exists() && complete.length()==asset.size && digest(complete)==asset.sha256)return@withContext complete
        if(complete.exists())check(complete.delete())
        val part=File(folder,asset.sha256+".part")
        if(part.length()>asset.size)check(part.delete())
        if(part.length()<asset.size) {
            val offset=part.length()
            require(folder.usableSpace==0L || folder.usableSpace>asset.size-offset+32_000_000L) { "空间不足，请至少释放 ${((asset.size-offset)/1_000_000)+32} MB" }
            request(asset.url,offset) { response ->
                checkStatus(response)
                val append=response.code==206
                if(append) {
                    val range=Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(response.header("Content-Range").orEmpty())
                        ?: error("服务器返回无效的续传范围")
                    require(range.groupValues[1].toLong()==offset && range.groupValues[2].toLong()==asset.size-1 && range.groupValues[3].toLong()==asset.size) { "续传范围不匹配，请重试" }
                } else require(response.code==200) { "下载响应异常" }
                var count=if(append)offset else 0
                var last=0L
                response.body!!.byteStream().use { input -> FileOutputStream(part,append).use { output ->
                    val buf=ByteArray(128*1024)
                    while(true) {
                        currentCoroutineContext().ensureActive()
                        val n=input.read(buf);if(n<0)break
                        require(count+n<=asset.size) { "下载大小超过 GitHub 声明值" }
                        output.write(buf,0,n);count+=n
                        if(System.nanoTime()-last>200_000_000L) { progress(WanxiangProgress("下载 / Downloading ${asset.name}",count,asset.size));last=System.nanoTime() }
                    }
                    output.fd.sync()
                } }
                require(count==asset.size) { "下载中断，下次点击可继续（$count / ${asset.size} bytes）" }
            }
        }
        currentCoroutineContext().ensureActive()
        progress(WanxiangProgress("校验 SHA-256 / Verifying ${asset.name}"))
        if(digest(part)!=asset.sha256) { part.delete();error("SHA-256 校验失败，已丢弃下载；当前词库未改变") }
        check(part.renameTo(complete)) { "无法保存下载文件" }
        complete
    }
}
