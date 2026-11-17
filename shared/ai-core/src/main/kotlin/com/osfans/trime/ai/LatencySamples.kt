// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

object LatencySamples {
    const val chinese="jintianxiawuwomenyaoheteamyiqitaolunxiangmujindu hexiayibujihua qingbamingtianzaoshangjiudianhuiyixuyaodewenjianzhenglihaofageiwo"
    const val english="Tomorrow morning we have a meeting with the team to discuss project progress and next week's plan. Pleaes send me teh updated documents before nine and keep the 123 test results."
    fun migrate(sample:String)=if(sample=="wojintianyoumeeting")chinese else sample
    fun before(chinese:Boolean)=if(chinese) "我们正在讨论周末聚餐，大家想吃清淡一点，也有人需要提前安排工作时间。接下来我想补充：" else "We are planning the weekend dinner and arranging the meeting schedule. Here is my suggestion: "
    fun after(chinese:Boolean)=if(chinese) "，请大家确认时间。" else ", please confirm the time."
    fun input(chinese:Boolean,enabled:Boolean=true,beforeLength:Int=50,afterLength:Int=0)=Protocol.context(if(chinese) this.chinese else english,before(chinese),after(chinese),enabled,beforeLength,afterLength)
}
