// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The automatic AI mode the settings offer (Android `AiMode`): what is requested while typing. Whatever the
/// mode, the assistant and emoji keys can still ask by hand once the person has agreed to cloud AI.
public enum AiMode: Int, CaseIterable, Sendable {
    case none, correction, assistant

    public var title: String {
        switch self {
        case .none: return "无"
        case .correction: return "仅纠错"
        case .assistant: return "AI 助手＋纠错"
        }
    }

    public static func of(_ c: AiConfig) -> AiMode {
        if !c.automatic { return .none }
        if c.assistantEnabled { return .assistant }
        return c.enabled ? .correction : .none
    }

    public func applying(to c: AiConfig) -> AiConfig {
        var copy = c
        let automatic = self != .none
        copy.enabled = automatic
        copy.automatic = automatic
        copy.assistantEnabled = self == .assistant
        return copy
    }
}

/// The long input used by the latency test and by the request preview (Android `LatencySamples`).
public enum AiLatencySamples {
    public static let chinese = "jintianxiawuwomenyaoheteamyiqitaolunxiangmujindu hexiayibujihua qingbamingtianzaoshangjiudianhuiyixuyaodewenjianzhenglihaofageiwo"
    public static let english = "Tomorrow morning we have a meeting with the team to discuss project progress and next week's plan. Pleaes send me teh updated documents before nine and keep the 123 test results."

    public static func before(_ chinese: Bool) -> String {
        chinese ? "我们正在讨论周末聚餐，大家想吃清淡一点，也有人需要提前安排工作时间。接下来我想补充：" : "We are planning the weekend dinner and arranging the meeting schedule. Here is my suggestion: "
    }

    public static func after(_ chinese: Bool) -> String {
        chinese ? "，请大家确认时间。" : ", please confirm the time."
    }

    public static func input(chinese isChinese: Bool, _ c: AiConfig) -> AiInput {
        AiStore.context(isChinese ? chinese : english, before: before(isChinese), after: after(isChinese), c: c)
    }
}
