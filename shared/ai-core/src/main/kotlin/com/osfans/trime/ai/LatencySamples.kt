// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

object LatencySamples {
    const val chinese="jintianxiawuwomenyaoheteamyiqitaolunxiangmujindu hexiayibujihua qingbamingtianzaoshangjiudianhuiyixuyaodewenjianzhenglihaofageiwo"
    const val english="Tomorrow morning we have a meeting with the team to discuss project progress and next week's plan. Pleaes send me teh updated documents before nine and keep the 123 test results."
    fun migrate(sample:String)=if(sample=="wojintianyoumeeting")chinese else sample
}
