// SPDX-License-Identifier: GPL-3.0-or-later
package input.zephyr.windows

import com.osfans.trime.ai.*
import kotlinx.serialization.Serializable
import javax.swing.JComboBox
import javax.swing.JTextField

/** Cached API metadata belongs to one endpoint, never to every policy. */
@Serializable
data class ModelListCache(val endpoint:String, val ids:List<String>, val catalog:ModelCatalog) {
    fun validate() {
        ModelsClient.listUrl(endpoint)
        require(ids.size<=2000 && ids.distinct().size==ids.size)
        require(ids.all { it.isNotBlank() && it.length<=256 && it.none { c -> c.isISOControl() } })
        catalog.validate()
    }
    companion object {
        fun from(endpoint:String, result:ModelsClient.Discovery, previous:ModelCatalog=ModelCatalog()):ModelListCache {
            require(result.ids.isNotEmpty()) { "No models returned / 接口未返回模型，原列表保留" }
            val catalog=if(result.definitions.isEmpty())previous else ModelCatalog(version="models-api",models=result.definitions.distinctBy { it.id }.map { fresh ->
                val old=previous.models.firstOrNull { it.id==fresh.id }
                fresh.copy(parameters=old?.parameters.orEmpty().filterNot { it.key=="reasoning_effort" }+fresh.parameters)
            })
            return ModelListCache(endpoint,result.ids.distinct().sorted(),catalog).also { it.validate() }
        }
    }
}

fun Policy.effectiveCatalog(apiEndpoint:String=endpoint):ModelCatalog =
    modelList?.takeIf { it.endpoint==apiEndpoint }?.catalog ?: if(apiEndpoint==endpoint)catalog else ModelCatalog()

/** Updating choices must never replace an unfinished, manually typed model ID. */
class EditableModelSelector:JComboBox<String>() {
    init { isEditable=true; maximumRowCount=14; prototypeDisplayValue="provider/model-name"; name="model-selector"; addItemListener { event -> if(event.stateChange==java.awt.event.ItemEvent.SELECTED)editor.item=event.item } }
    private val textField get()=editor.editorComponent as JTextField
    val document get()=textField.document
    var text:String
        get()=textField.text
        set(value) { selectedItem=value; textField.text=value }
    fun setOptions(ids:List<String>) {
        val current=text
        val options=(listOf(current)+ids).filter { it.isNotBlank() }.distinct()
        removeAllItems();options.forEach { addItem(it) }
        text=current
    }
}
