// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.rime

import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.File
import java.io.RandomAccessFile
import java.util.zip.ZipFile

/** Deploy and verify this schema; preserve other enabled schemes and unrelated settings. */
fun interface WanxiangActivator { suspend fun activate(schema:String) }

class WanxiangUpdater(
    val directory:File,
    private val activator:WanxiangActivator,
    private val network:WanxiangNetwork=WanxiangNetwork(),
    private val catalog:suspend (Boolean)->WanxiangRelease=network::release,
    private val progress:(WanxiangProgress)->Unit={},
    private val bundledDirectory:File?=null,
    private val iceCatalog:suspend ()->WanxiangRelease=network::iceRelease,
) {
    val workspace=File(directory,".zephyr-wanxiang")
    private val stateFile=File(workspace,"state.json")
    private val journal=File(workspace,"transaction")
    private val legacySnapshots=listOf("default.custom.yaml","user.yaml","zephyr_wanxiang.schema.yaml",".zephyr-wanxiang/state.json")
    private val snapshots=legacySnapshots+"rime_ai_simp.schema.yaml"
    @Serializable private data class Transaction(val previousSchema:String,val existing:List<String>,val paths:List<String>?=null)

    fun state():WanxiangState {
        val file=if(stateFile.exists())stateFile else File(stateFile.path+".bak")
        val bundled=bundledDirectory?.let { File(it,"zephyr-dictionaries.json") }?.takeIf { it.isFile }
            ?.let { wanxiangJson.decodeFromString<WanxiangState>(it.readText()) } ?: WanxiangState()
        val saved=if(file.exists())wanxiangJson.decodeFromString<WanxiangState>(file.readText()) else {
            val selected=File(directory,"user.yaml").takeIf {it.isFile}?.readLines()?.firstOrNull {it.trimStart().startsWith("previously_selected_schema:")}
                ?.substringAfter(':')?.trim()?.trim('\"','\'')
            val previousIce=selected==FALLBACK || (selected==null && File(directory,"default.custom.yaml").takeIf {it.isFile}?.readText()?.let {it.contains("schema: $FALLBACK") && !it.contains("schema: $SCHEMA")}==true)
            bundled.copy(enabled=if(previousIce)false else bundled.enabled)
        }
        return saved.copy(dictionary=saved.dictionary ?: bundled.dictionary,iceDictionary=saved.iceDictionary ?: bundled.iceDictionary)

    }
    private fun resource(name:String):File = File(directory,name).takeIf { it.exists() }
        ?: bundledDirectory?.let { File(it,name) } ?: File(directory,name)
    private fun usableModel(s:WanxiangState)=s.model?.takeIf { File(directory,modelName(it)+".gram").length()==it.asset.size }
    /** Select an installed dictionary without network access; keep the grammar preference across switches. */
    suspend fun selectDictionary(wanxiang:Boolean,grammar:Boolean=state().grammar)=locked {
        recover();val current=state()
        check(!wanxiang || current.dictionary!=null) { "请先安装包含万象词表的新版应用" }
        activate(current.copy(enabled=wanxiang,grammar=grammar))
    }
    /** Update either dictionary without downloading a model or changing the user's selected dictionary. */
    suspend fun updateDictionary(wanxiang:Boolean)=locked {
        recover();progress(WanxiangProgress("检查 GitHub 词表更新 / Checking dictionary…"))
        val release=if(wanxiang)catalog(false) else iceCatalog()
        if(wanxiang)ensureDictionary(release) else ensureIce(release)
        val current=state()
        activate(if(wanxiang)current.copy(dictionary=release) else current.copy(iceDictionary=release))
    }
    suspend fun updateModel()=locked {
        recover();progress(WanxiangProgress("检查万象语法模型 / Checking grammar model…"))
        val release=catalog(true);ensureModel(release)
        activate(state().copy(model=release,grammar=true))
    }
    private suspend fun ensureDictionary(release:WanxiangRelease) {
        if(resource(dictName(release)+".dict.yaml").isFile)return
        val zip=network.download(release.asset,File(workspace,"downloads"),progress)
        progress(WanxiangProgress("展开万象词表 / Extracting Wanxiang…"));extract(zip,release)
    }
    private suspend fun ensureIce(release:WanxiangRelease) {
        if(resource(iceName(release)+".dict.yaml").isFile)return
        val zip=network.download(release.asset,File(workspace,"downloads"),progress)
        progress(WanxiangProgress("展开雾凇词表 / Extracting Rime Ice…"))
        val name=iceName(release)
        extractFiles(zip,name,ICE_DICTIONARIES.map { "cn_dicts/$it.dict.yaml" }.toSet())
        writeSafely(File(directory,"$name.dict.yaml"),dictionaryManifest(name,ICE_DICTIONARIES.map { "${name}_data/cn_dicts/$it" }))
        writeSafely(File(workspace,"Rime-Ice-NOTICE.txt"),"Rime Ice · iDvel and contributors\nhttps://github.com/iDvel/rime-ice\nGPL-3.0-only. ${release.version} / ${release.asset.sha256}\nOriginal dictionary text and source attribution are retained; Zephyr adapts the schema and import paths.\n")
    }
    private suspend fun ensureModel(release:WanxiangRelease) {
        val target=File(directory,modelName(release)+".gram")
        if(target.isFile && target.length()==release.asset.size && digest(target)==release.asset.sha256)return
        val file=network.download(release.asset,File(workspace,"downloads"),progress)
        if(target.exists())error("现有模型校验失败，请先切换雾凇并修复：${target.name}")
        check(file.renameTo(target)) { "无法保存语法模型" }
    }
    private suspend fun <T> locked(block:suspend ()->T):T=withContext(Dispatchers.IO) {
        workspace.mkdirs()
        RandomAccessFile(File(workspace,"update.lock"),"rw").use { file ->
            val lock=try { file.channel.tryLock() } catch(_:java.nio.channels.OverlappingFileLockException) { null }
            check(lock!=null) { "另一个词库更新正在进行 / Another update is running" }
            try { block() } finally { lock.release() }
        }
    }
    suspend fun update(grammar:Boolean=true)=locked {
        recover()
        progress(WanxiangProgress("检查 GitHub 最新发布 / Checking releases…"))
        val dictionary=catalog(false)
        val model=if(grammar)catalog(true) else state().model
        val current=state()
        if(current.enabled && current.grammar==grammar && current.dictionary==dictionary && (!grammar || current.model==model) && installedFiles(current)) {
            // The user may have switched schemes elsewhere since the previous update.
            // This button promises to use Wanxiang even when no download is necessary.
            activate(current)
            progress(WanxiangProgress("已是最新版本 / Up to date"));return@locked
        }
        ensureDictionary(dictionary)
        if(grammar)ensureModel(requireNotNull(model))
        currentCoroutineContext().ensureActive()
        activate(current.copy(enabled=true,grammar=grammar,dictionary=dictionary,model=model))
    }
    suspend fun useFallback()=locked {
        recover();activate(state().copy(enabled=false))
    }
    private fun installedFiles(s:WanxiangState):Boolean = s.dictionary?.let {
        resource("${dictName(it)}.dict.yaml").isFile && File(directory,"zephyr_wanxiang.schema.yaml").isFile &&
            (!s.grammar || s.model?.let { m -> File(directory,modelName(m)+".gram").length()==m.asset.size }==true)
    }==true

    private fun begin(previous:String) {
        check(!File(journal,"pending.json").exists()) { "有待恢复的更新" }
        journal.mkdirs()
        val existing=snapshots.filter { File(directory,it).exists() }
        for((i,path) in snapshots.withIndex()) if(path in existing)File(directory,path).copyTo(File(journal,"$i.backup"),overwrite=true)
        writeSafely(File(journal,"pending.json"),wanxiangJson.encodeToString(Transaction(previous,existing,snapshots)))
    }
    private suspend fun recover() {
        val pending=File(journal,"pending.json")
        if(!pending.exists())return
        withContext(NonCancellable) {
            progress(WanxiangProgress("恢复上次配置 / Restoring previous configuration…",canCancel=false))
            val transaction=wanxiangJson.decodeFromString<Transaction>(pending.readText())
            for((i,path) in (transaction.paths ?: legacySnapshots).withIndex()) {
                val target=File(directory,path)
                if(path in transaction.existing)writeSafely(target,File(journal,"$i.backup").readBytes())
                else if(target.exists())check(target.delete())
            }
            invalidateCompiledSchemas()
            activator.activate(transaction.previousSchema)
            check(pending.delete())
        }
    }
    // Rime compares schema versions as dotted integers, and source timestamps at one-second precision.
    // Managed versions stay above bundled ones; remove only our generated configs to force each toggle.
    private fun invalidateCompiledSchemas() {
        val build=File(directory,"build")
        for(id in listOf(SCHEMA,FALLBACK)) {
            val file=File(build,"$id.schema.yaml")
            if(file.isFile && file.canonicalFile.parentFile==build.canonicalFile)check(file.delete()) {"无法刷新词库配置，请关闭输入后重试"}
        }
    }
    private fun verifyCompiledSchema(next:WanxiangState) {
        val file=File(directory,"build/${if(next.enabled)SCHEMA else FALLBACK}.schema.yaml")
        if(!file.isFile)return // Some embedders use a separate staging directory.
        val text=file.readText()
        val expected=if(next.enabled)next.dictionary?.let(::dictName) else next.iceDictionary?.let(::iceName)
        check(expected==null || text.contains("dictionary: $expected")) {"Rime 未加载所选词表"}
        if(next.enabled) {
            val model=if(next.grammar)usableModel(next) else null
            check(if(model!=null)text.contains("language: ${modelName(model)}") else !text.contains("grammar:")) {"Rime 未应用语法模型开关"}
        }
    }
    // Keep a selected bundled snapshot in user storage so future APK/Setup updates cannot invalidate it.
    private fun cacheBundled(release:WanxiangRelease,wanxiang:Boolean) {
        val name=if(wanxiang)dictName(release) else iceName(release)
        if(File(directory,"$name.dict.yaml").isFile)return
        val shared=bundledDirectory ?: return
        if(!File(shared,"$name.dict.yaml").isFile)return
        val tablePaths=if(wanxiang)DICTIONARIES.map { "dicts/$it" } else ICE_DICTIONARIES.map { "cn_dicts/$it" }
        val target=File(directory,"${name}_data")
        val stage=File(workspace,"$name.bundle").apply {mkdirs()}
        for(path in tablePaths) {
            val input=File(shared,(if(wanxiang) "${name}_data/" else "")+path+".dict.yaml")
            val output=File(stage,path+".dict.yaml");output.parentFile.mkdirs();input.copyTo(output,overwrite=true)
        }
        if(target.exists())check(target.deleteRecursively())
        check(stage.renameTo(target))
        if(wanxiang)writeSafely(File(directory,"${name}_algebra.yaml"),File(shared,"${name}_algebra.yaml").readBytes())
        writeSafely(File(directory,"$name.dict.yaml"),dictionaryManifest(name,tablePaths.map {"${name}_data/$it"}))
    }
    private suspend fun activate(next:WanxiangState) = withContext(NonCancellable) {
        val old=state()
        progress(WanxiangProgress("部署并启用 / Deploying… 首次需几分钟",canCancel=false))
        next.dictionary?.let {cacheBundled(it,true)}
        next.iceDictionary?.let {cacheBundled(it,false)}
        begin(if(old.enabled && old.dictionary!=null)SCHEMA else FALLBACK)
        try {
            next.dictionary?.let { writeSafely(File(directory,"$SCHEMA.schema.yaml"),schema(it,if(next.enabled && next.grammar)usableModel(next) else null)) }
            next.iceDictionary?.let { writeSafely(File(directory,"$FALLBACK.schema.yaml"),iceSchema(it)) }
            invalidateCompiledSchemas()
            activator.activate(if(next.enabled)SCHEMA else FALLBACK)
            verifyCompiledSchema(next)
            writeSafely(stateFile,wanxiangJson.encodeToString(next))
            check(File(journal,"pending.json").delete())
            runCatching { cleanup(next,old) }
            progress(WanxiangProgress("已启用 / Ready\n${next.summary()}",canCancel=false))
        } catch(error:Exception) {
            try { recover() } catch(restore:Exception) {
                error.addSuppressed(restore)
                throw IllegalStateException("部署失败，恢复仍待完成；重新点击更新可重试恢复。${error.message}",error)
            }
            throw IllegalStateException("部署失败，已恢复原词库：${error.message}",error)
        }
    }
    /** Only updater-owned versioned assets; retain current + previous for recovery. Never touch user DBs. */
    private fun cleanup(next:WanxiangState, old:WanxiangState) {
        val keep=(listOfNotNull(next.dictionary,old.dictionary).flatMap { listOf(dictName(it),dictName(it)+"_data",dictName(it)+"_algebra") }+
            listOfNotNull(next.model,old.model).map(::modelName)+
            listOfNotNull(next.iceDictionary,old.iceDictionary).flatMap {listOf(iceName(it),iceName(it)+"_data")} ).toSet()
        val owned=Regex("zephyr_(?:wanxiang|ice)_(?:d_[0-9a-f]{12}(?:_data|_algebra)?|m_[0-9a-f]{12})(?:\\.dict\\.yaml|\\.yaml|\\.gram)?")
        directory.listFiles().orEmpty().filter { owned.matches(it.name) }.forEach { file ->
            val stem=file.name.removeSuffix(".dict.yaml").removeSuffix(".yaml").removeSuffix(".gram")
            if(stem !in keep && file.canonicalFile.parentFile==directory.canonicalFile)runCatching { file.deleteRecursively() }
        }
        val build=File(directory,"build")
        build.listFiles().orEmpty().filter { it.name.matches(Regex("zephyr_(?:wanxiang|ice)_d_[0-9a-f]{12}\\.(?:table|reverse|prism)\\.bin")) }.forEach { file ->
            if(file.name.substringBefore('.') !in keep && file.canonicalFile.parentFile==build.canonicalFile)file.delete()
        }
        // On success obsolete transfer files are disposable. Failed/paused updates never reach cleanup.
        File(workspace,"downloads").listFiles().orEmpty().filter { it.name.matches(Regex("[0-9a-f]{64}\\.(?:download|part)")) }.forEach { it.delete() }
    }

    private fun extractFiles(zip:File,name:String,required:Set<String>):File {
        val target=File(directory,name+"_data")
        val staging=File(workspace,name+".extract")
        if(staging.exists())check(staging.deleteRecursively())
        staging.mkdirs()
        val found=mutableSetOf<String>()
        var expanded=0L
        ZipFile(zip).use { archive ->
            val entries=archive.entries()
            while(entries.hasMoreElements()) {
                val entry=entries.nextElement()
                val parts=entry.name.replace('\\','/').split('/')
                require(!entry.name.startsWith('/') && ':' !in entry.name && parts.none { it==".." }) { "词库压缩包包含非法路径" }
                if(entry.isDirectory || entry.name !in required)continue
                require(found.add(entry.name)) { "词库压缩包包含重复文件" }
                val output=File(staging,entry.name)
                output.parentFile.mkdirs()
                archive.getInputStream(entry).use { input -> output.outputStream().use { stream ->
                    val buf=ByteArray(64*1024)
                    while(true) { val count=input.read(buf);if(count<0)break;expanded+=count;require(expanded<200_000_000L) { "词库展开后过大" };stream.write(buf,0,count) }
                } }
                require(output.length()>0) { "词库文件为空" }
            }
        }
        require(found==required) { "压缩包缺少必要词库：${required-found}" }
        // Data filenames are digest-specific; active dictionaries are never overwritten in place.
        if(target.exists())check(target.deleteRecursively())
        check(staging.renameTo(target))
        return target
    }
    internal fun extract(zip:File, release:WanxiangRelease) {
        val name=dictName(release)
        val target=extractFiles(zip,name,(DICTIONARIES.map { "dicts/$it.dict.yaml" }+"wanxiang_algebra.yaml").toSet())
        writeSafely(File(directory,"${name}_algebra.yaml"),File(target,"wanxiang_algebra.yaml").readBytes())
        val dictionary="---\nname: $name\nversion: '${release.asset.sha256.take(12)}'\nsort: by_weight\nuse_preset_vocabulary: false\nimport_tables:\n"+
            DICTIONARIES.joinToString("\n") { "  - ${name}_data/dicts/$it" }+"\n...\n"
        writeSafely(File(directory,"$name.dict.yaml"),dictionary)
        val license=javaClass.getResourceAsStream("/rime/wanxiang-CC-BY-4.0.txt") ?: error("缺少万象资源许可")
        license.use { writeSafely(File(workspace,"CC-BY-4.0.txt"),it.readBytes()) }
        writeSafely(File(workspace,"NOTICE.txt"),"万象拼音 / Wanxiang · amzxyz and contributors\nhttps://github.com/amzxyz/rime-wanxiang\nhttps://github.com/amzxyz/rime-wanxiang-data\nData: CC BY 4.0. ${release.version} / ${release.asset.sha256}\nZephyr adapts the full-pinyin schema, file paths and dictionary manifest. Upstream data is unmodified. No upstream updater code is included.\n")
    }
    companion object {
        val ICE_DICTIONARIES=listOf("8105","base","ext","tencent","others")
        fun iceName(release:WanxiangRelease)="zephyr_ice_d_"+release.asset.sha256.take(12)
        fun dictionaryManifest(name:String,tables:List<String>)="---\nname: $name\nversion: '1'\nsort: by_weight\nuse_preset_vocabulary: false\nimport_tables:\n"+tables.joinToString("\n") { "  - $it" }+"\n...\n"+if(name.startsWith("zephyr_ice_"))WanxiangUpdater::class.java.getResourceAsStream("/rime/ice-extra-entries.txt")!!.bufferedReader().use {it.readText()} else ""
        fun iceSchema(release:WanxiangRelease):String = WanxiangUpdater::class.java.getResourceAsStream("/rime/zephyr_ice.schema.yaml")!!.bufferedReader().use {it.readText()}
            .replace("@@DICT@@",iceName(release)).replace("@@VERSION@@","1000.0")
        const val SCHEMA="zephyr_wanxiang"
        const val FALLBACK="rime_ai_simp"
        val DICTIONARIES=listOf("zi","jichu","cuoyin","duoyin","diming","mingren","yiren")
        fun dictName(release:WanxiangRelease)="zephyr_wanxiang_d_"+release.asset.sha256.take(12)
        fun modelName(release:WanxiangRelease)="zephyr_wanxiang_m_"+release.asset.sha256.take(12)
        fun schema(dictionary:WanxiangRelease,model:WanxiangRelease?):String {
            val name=dictName(dictionary)
            val template=WanxiangUpdater::class.java.getResourceAsStream("/rime/zephyr_wanxiang.schema.yaml")!!.bufferedReader().use { it.readText() }
            return template.replace("@@DICT@@",name).replace("@@VERSION@@","1000.0")+
                if(model==null) "" else "\ngrammar:\n  language: ${modelName(model)}\n  collocation_max_length: 6\n  collocation_min_length: 2\n  collocation_penalty: -14\n  non_collocation_penalty: -6\n  weak_collocation_penalty: -100\n  rear_penalty: -18\n"
        }
    }
}
